-- Alerts when a ticket comes back for validation.
--
-- A run claims its ticket `NEXT` and its write-back flips it to `TEST`; that
-- flip is the one the user has to act on -- run the change, validate it,
-- promote it to `DONE`. The run happens in its own tmux pane, often while nvim
-- sits in another window or behind another application, so the change has to
-- reach the user where they are: the editor notification (vim.notify, which
-- nvim-notify draws and `:Notifications` keeps), the tmux status line, and a
-- desktop notification for when nvim is not the focused window.
--
-- What it reads is the org tree's own file events (helpers/org/watch.lua),
-- which name the files that changed. A changed file is parsed from disk -- not
-- from the buffer, which helpers/org/ai.lua's sync is about to reload -- and
-- the state of every entry carrying an `:ID:` is compared with the state the
-- module recorded the last time it read that file. The vault is read once at
-- setup to give that record its first version: the ticket a run is about to
-- close may have been claimed before this nvim started.
--
-- A change nvim made itself (helpers/org/write.lua's M.wrote) is read -- the
-- record stays the file's -- but not announced: the user moved that ticket in
-- a view and is looking right at it.
local M = {}

local watch = require 'helpers.org.watch'
local write = require 'helpers.org.write'

--- The transition worth telling the user about: the run is done, the ticket is
--- theirs to check.
local FROM, TO = 'NEXT', 'TEST'

--- `normalized path -> { [id] = { state = 'NEXT', title = '...' } }`: the
--- states this module saw last time it read the file.
---@type table<string, table<string, { state: string|nil, title: string }>>
local known = {}

--- Whether nvim itself is the focused window: the desktop and tmux notices are
--- for the user who is somewhere else.
local focused = true

--- The entries of a parsed `lines` that can be told apart across two reads:
--- keyed by `:ID:` when they carry one, by title when they do not.
---@param lines string[]
---@param path string
---@return table<string, { state: string|nil, title: string }>|nil
local function states(lines, path)
  local ok, parsed = pcall(require('org.parser').parse, lines, path)
  if not ok or not parsed then
    return nil
  end
  local out = {}
  for _, hl in ipairs(parsed.headlines) do
    local title = hl:plain_title()
    local id = hl.properties and hl.properties.ID
    local key = (id and id ~= '') and id or ('title:' .. title)
    out[key] = { state = hl.todo, title = title }
  end
  return out
end

--- Parse `path` off disk, or nil when it is not readable (deleted, or a write
--- that has not landed yet).
---@param path string
---@return table<string, { state: string|nil, title: string }>|nil
local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' then
    return nil
  end
  return states(lines, path)
end

--- Does the file hold a ticket in flight? Everything else -- a node's notes,
--- the archive -- has no `NEXT` to leave, so the startup read skips parsing it.
---@param lines string[]
---@return boolean
local function in_flight(lines)
  for _, line in ipairs(lines) do
    if line:match '^%*+ NEXT%s' then
      return true
    end
  end
  return false
end

--- A desktop notification, detached: a missing notifier (a bare terminal, a
--- server with no session bus) is not an error the user needs to read.
---@param title string
---@param body string
local function desktop(title, body)
  if vim.fn.executable 'notify-send' ~= 1 then
    return
  end
  pcall(vim.system, { 'notify-send', '-a', 'nvim', '-u', 'normal', title, body }, { detach = true })
end

--- One line on the tmux status bar of the client nvim runs under.
---@param msg string
local function tmux_message(msg)
  if (vim.env.TMUX or '') == '' then
    return
  end
  pcall(vim.system, { 'tmux', 'display-message', '-d', '8000', msg })
end

--- Tell the user the ticket is theirs again, on every channel they may be
--- reading.
---@param title string
local function announce(title)
  local msg = title .. ' is ready for you to check'
  require('org.utils').notify(msg)
  if focused then
    return
  end
  desktop('nvim: a ticket is ready', msg)
  tmux_message('🤖 ' .. msg)
end

--- Read the files the watcher named and announce the tickets that left `NEXT`
--- for `TEST` since the last read.
---@param paths string[]
function M.sync(paths)
  for _, path in ipairs(paths or {}) do
    local after = read(path)
    if not after then
      known[path] = nil
    else
      local before = known[path]
      local own = write.wrote(path)
      for key, now in pairs(after) do
        local was = before and before[key]
        if was and was.state == FROM and now.state == TO and not own then
          announce(now.title)
        end
      end
      known[path] = after
    end
  end
end

--- Read every org file of the tree that holds a ticket in flight, so the first
--- `TEST` a run writes is compared against the `NEXT` it claimed.
---@param root string
local function seed(root)
  for _, path in ipairs(vim.fn.globpath(root, '**/*.org', false, true)) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok and type(lines) == 'table' and in_flight(lines) then
      known[vim.fs.normalize(path)] = states(lines, vim.fs.normalize(path)) or {}
    end
  end
end

function M.setup()
  vim.api.nvim_create_autocmd('FocusGained', {
    callback = function()
      focused = true
    end,
    desc = 'org alerts: the user is looking at nvim again',
  })
  vim.api.nvim_create_autocmd('FocusLost', {
    callback = function()
      focused = false
    end,
    desc = 'org alerts: the user is elsewhere, so a ticket gets announced there too',
  })
  local ok, cfg = pcall(require, 'org.config')
  local root = vim.fs.normalize(vim.fn.expand((ok and cfg.opts and cfg.opts.org_directory) or '~/org'))
  seed(root)
  watch.subscribe(M.sync)
end

return M
