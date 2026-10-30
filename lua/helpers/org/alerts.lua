-- Alerts when a ticket comes back for validation.
--
-- A run claims its ticket `NEXT` and its write-back leaves it in a state the
-- user owns: `TEST` (run the change, validate it, promote it to `DONE`),
-- `WARN` (it stopped without finishing) or `PEND` (it has a question). The run
-- happens in its own tmux pane, often while nvim sits in another window or
-- behind another application, so the change has to reach the user where they
-- are: the editor notification (vim.notify, which nvim-notify draws and
-- `:Notifications` keeps), the tmux status line, and a desktop notification
-- for when nvim is not the focused window.
--
-- The status line is the only one of the three that outlives the moment: it
-- carries a segment of its own, `@omp_alert` (see `status-right` in
-- `~/.tmux.conf`), so a run that finishes while the user is looking elsewhere
-- leaves a mark at the bottom of the screen until the ticket is dealt with --
-- and the mark goes when it is, because the same read that raises it drops it
-- as soon as the state leaves `TEST`/`WARN`/`PEND`. An option rather than a file
-- the bar prints: the value is the segment, so the bar needs no command of its
-- own to read it, and a redraw costs tmux nothing.
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

--- The states a run leaves behind that are the user's to act on, and how the
--- status line names them.
local FINISHED = { TEST = 'to check', WARN = 'failed', PEND = 'waiting on you' }

--- The order the status line lists them in: what the user is asked to look at
--- first, then what broke, then what waits on an answer.
local ORDER = { 'TEST', 'WARN', 'PEND' }

--- The tmux option the status line prints as its notice segment. Server-wide,
--- not per client, so every attached screen shows the same tickets -- they are
--- the vault's, not one window's.
local OPTION = '@omp_alert'

--- The tickets announced and not yet dealt with, by `:ID:`:
--- `{ state = 'TEST', title = '...', file = '<normalized path>' }`. A ticket
--- leaves the set on the read that finds it in any other state, which is the
--- user acting on it (`TEST` -> `DONE`) or a relaunch claiming it again.
---@type table<string, { state: string, title: string, file: string }>
local pending = {}

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

--- Write what the status line shows: one segment per state, in `ORDER`, naming
--- how many tickets of it are waiting (`🤖 1 to check · 2 failed`), or no
--- segment at all when nothing is -- the bar is a mirror of the tickets, never a
--- log. Detached: a bar that is behind a slow client must not hold up the read
--- that raised it, and no tmux at all is not an error worth reading.
local function publish()
  local count = {}
  for _, item in pairs(pending) do
    count[item.state] = (count[item.state] or 0) + 1
  end
  local parts = {}
  for _, state in ipairs(ORDER) do
    if count[state] then
      parts[#parts + 1] = count[state] .. ' ' .. FINISHED[state]
    end
  end
  local seg = #parts > 0 and ('🤖 ' .. table.concat(parts, ' · ')) or ''
  local argv = seg == '' and { 'tmux', 'set-option', '-gu', OPTION } or { 'tmux', 'set-option', '-g', OPTION, seg }
  pcall(vim.system, argv, { detach = true })
end

--- Tell the user the ticket is theirs again, on every channel they may be
--- reading. The tmux side is not in here: its bar carries the notice itself
--- (`@omp_alert`), and a `display-message` over the bar would hide the very
--- segment that stays.
---@param title string
---@param state string
local function announce(title, state)
  local msg = title .. (state == 'TEST' and ' is ready for you to check' or ' needs you: ' .. FINISHED[state])
  require('org.utils').notify(msg, state == 'TEST' and vim.log.levels.INFO or vim.log.levels.WARN)
  if focused then
    return
  end
  desktop('nvim: a ticket is ready', msg)
end

--- Read the files the watcher named and announce the tickets that left `NEXT`
--- for a state the user owns since the last read, and forget the ones that
--- left such a state.
---@param paths string[]
function M.sync(paths)
  local raised = false
  for _, path in ipairs(paths or {}) do
    local after = read(path)
    if not after then
      known[path] = nil
    else
      local before = known[path]
      local own = write.wrote(path)
      for key, now in pairs(after) do
        local was = before and before[key]
        if was and was.state ~= now.state then
          if FINISHED[now.state] then
            -- nvim wrote this one itself: the user moved it in a view and is
            -- looking right at it, so the moment needs no telling
            if not own then
              pending[key] = { state = now.state, title = now.title, file = path }
              announce(now.title, now.state)
              raised = true
            end
          elseif pending[key] then
            pending[key] = nil
            raised = true
          end
        end
      end
      -- a ticket the file no longer holds is not one to keep showing
      for key, item in pairs(pending) do
        if item.file == path and not after[key] then
          pending[key] = nil
          raised = true
        end
      end
      known[path] = after
    end
  end
  if raised then
    publish()
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
  vim.api.nvim_create_autocmd('VimLeavePre', {
    callback = function()
      -- nothing is ours to show once the nvim that knew the tickets is gone
      pending = {}
      publish()
    end,
    desc = 'org alerts: leave the status line clean',
  })
  local ok, cfg = pcall(require, 'org.config')
  local root = vim.fs.normalize(vim.fn.expand((ok and cfg.opts and cfg.opts.org_directory) or '~/org'))
  seed(root)
  -- a notice left by an nvim that did not get to clear it is not this one's
  publish()
  watch.subscribe(M.sync)
end

return M
