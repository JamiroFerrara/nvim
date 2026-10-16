-- Rolling a board (wired in lua/terminal_plugins/org.nvim.lua).
--
-- `<leader>oD` (the `archive_all_done` action, replaced here) sweeps every
-- finished ticket off the current board into a file per client per month --
-- ~/org/archive/<client>/<YYYY-MM>.org_archive -- and reports what it moved.
-- `<leader>oA` is the same sweep with a grace window: only tickets that closed
-- more than `GRACE_DAYS` ago, so a mis-tapped `DONE` is not carried away the
-- moment it happens. `<leader>oU` is the inverse: it moves the archived entry
-- at point back into its board, under the parent the drawer recorded.
--
-- Three facts drive the shape:
--
--   * `archive_subtree` sends the entry to `location_for()`: the headline's
--     inherited `:ARCHIVE:` property, else the file's `#+ARCHIVE:` keyword,
--     else `config.opts.archive_location`. The first two hold one path and
--     the month changes every month, so the sweep sets the third for the
--     duration of the run and restores it: no keyword to keep in sync in
--     nine boards, and no stale path left behind for next month. A board
--     that sets a `#+ARCHIVE:` keyword of its own is reported, not overridden
--     -- the plugin's precedence is respected.
--   * A file may host several workstreams (`* Allitude` and `* PMS` in one
--     board), so the sweep walks the children of *every* level-1 tree rather
--     than the children of the headline under the cursor. The key stops
--     depending on where the cursor happens to be.
--   * Only a subtree with no open TODO rolls (`has_open_todo`, the plugin's
--     `archive_all_done` predicate): a ticket left at TEST/WARN/PEND is still
--     waiting for something and stays on the board. `DONE` is the only
--     keyword that leaves it.
--
-- Why the sweep is not silent: an archive file is invisible to the agenda
-- (`agenda_files` matches `*.org`, not `*.org_archive`) and to the roam index,
-- so an entry that rolls before its findings were extracted is out of sight of
-- both the user and the agent. The report names the ones it moved that were
-- big enough to have said something -- over `BIG_ENTRY_LINES` lines -- and
-- carry no knowledge-base link. It is a message, never a prompt: the sweep
-- stays one keypress.
local M = {}

--- Closed tickets older than this roll on `<leader>oA`, in days.
local GRACE_DAYS = 7

--- An entry over this many lines that carries no KB link is reported.
local BIG_ENTRY_LINES = 15

local function notify(msg, level)
  require('org.utils').notify(msg, level)
end

--- The board's key: its basename. The same string is the roam node's tag and
--- the archive directory's name, so one word names the project everywhere.
---@param path string
---@return string
local function client_of(path)
  return vim.fn.fnamemodify(path, ':t:r')
end

--- Where this month's closed tickets go. `%s` is not used: the location is
--- resolved by parse_location against the source file's directory, and an
--- absolute path with `~` expands in utils.expand.
---@param client string
---@param when? string
---@return string
local function archive_location(client, when)
  return string.format('~/org/archive/%s/%s.org_archive::', client, when or os.date '%Y-%m')
end

--- Run `fn` with `archive_location` pointed at `path`, restoring it after.
--- Also refuse to run when the buffer sets its own location.
local function with_archive_location(path, fn)
  local config = require('org.config')
  local saved = config.opts.archive_location
  config.opts.archive_location = path
  local ok, a, b = pcall(fn)
  config.opts.archive_location = saved
  if not ok then
    error(a, 0)
  end
  return a, b
end

--- A subtree with no open TODO anywhere inside it, the plugin's own predicate
--- for `archive_all_done` (org's `org-archive-all-done`).
---@param hl org.Headline
---@return boolean
local function has_open_todo(hl)
  if hl:is_todo() then
    return true
  end
  for _, child in ipairs(hl.children or {}) do
    if has_open_todo(child) then
      return true
    end
  end
  return false
end

--- `hl` closed at least `days` ago. `Date:days_from_today()` is negative for
--- the past (it is `self:days() - today:days()`).
---@param hl org.Headline
---@param days integer
---@return boolean
local function closed_before(hl, days)
  local closed = hl.planning and hl.planning.closed
  if not closed then
    return false
  end
  return -closed:days_from_today() >= days
end

--- Children of every level-1 tree of `bufnr` that `predicate` accepts.
---@param bufnr integer
---@param predicate fun(hl: org.Headline): boolean
---@return org.Headline[]
local function candidates(bufnr, predicate)
  local file = require('org.files').get_buffer(bufnr)
  local out = {}
  for _, top in ipairs(file.children or {}) do
    for _, child in ipairs(top.children or {}) do
      if predicate(child) then
        out[#out + 1] = child
      end
    end
  end
  return out
end

--- The entries big enough to have said something, with nothing linking them
--- into the knowledge base: the ones the report names.
---@param bufnr integer
---@param list org.Headline[]
---@return string[]
local function unextracted(bufnr, list)
  local out = {}
  for _, hl in ipairs(list) do
    local lines = vim.api.nvim_buf_get_lines(bufnr, hl.line, hl.end_line, false)
    if #lines > BIG_ENTRY_LINES then
      local text = table.concat(lines, '\n')
      local linked = text:find('KB_SOURCES', 1, true)
        or text:find('kb/fact', 1, true)
        or text:find('[[id:', 1, true)
        or text:find('roam:', 1, true)
      if not linked then
        out[#out + 1] = hl:plain_title()
      end
    end
  end
  return out
end

--- The sweep. `predicate` decides the candidates; every one of them is moved,
--- no confirmation, following the marks the plugin's own `archive_all_matches`
--- uses so an entry that shifts (or moves away with its parent) is found again
--- rather than archived twice.
---@param predicate fun(hl: org.Headline): boolean
---@param what string the word the report uses ("finished" / "closed over N days ago")
local function sweep(predicate, what)
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= 'org' then
    notify('org roll: not an org buffer', vim.log.levels.WARN)
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' or path:match '%.org_archive$' then
    notify('org roll: run this from a board, not an archive', vim.log.levels.WARN)
    return
  end

  local file = require('org.files').get_buffer(bufnr)
  -- location_for() prefers a headline's inherited `:ARCHIVE:` property and then
  -- the file's `#+ARCHIVE:` keyword over config.opts.archive_location, so a
  -- board that pins either would send entries somewhere else than the roll
  -- reports -- and split one project's history over two files. Refuse and name
  -- the pin instead of guessing.
  local pinned = file.settings.archive
  if not (pinned and pinned ~= '') then
    for _, top in ipairs(file.children or {}) do
      for _, child in ipairs(top.children or {}) do
        local h = child
        while h do
          if h.properties.ARCHIVE and h.properties.ARCHIVE ~= '' then
            pinned = h.properties.ARCHIVE
            break
          end
          h = h.parent
        end
        if pinned then
          break
        end
      end
      if pinned then
        break
      end
    end
  end
  if pinned then
    notify(
      string.format(
        'org roll: this board pins its archive location (%s), which wins over the monthly file. Remove it to roll into ~/org/archive/<client>/<YYYY-MM>.org_archive, or use <prefix>$ for a one-off.',
        pinned
      ),
      vim.log.levels.WARN
    )
    return
  end

  local list = candidates(bufnr, predicate)
  if #list == 0 then
    notify('org roll: no ' .. what .. ' ticket to roll')
    return
  end
  local flagged = unextracted(bufnr, list)

  local client = client_of(path)
  local target = archive_location(client)
  local archive = vim.fn.expand(target:gsub('::$', ''))
  -- archive_subtree rolls its own work back when the archive file cannot be
  -- written ("Archive not saved, subtree kept"), so the directory has to be
  -- there before the first entry of a new month is moved into it.
  vim.fn.mkdir(vim.fs.dirname(archive), 'p')

  local moved = with_archive_location(target, function()
    return require('org.marks').with(function(track)
      local marks = {}
      for _, hl in ipairs(list) do
        marks[#marks + 1] = track(bufnr, hl.line, nil, { invalidate = true })
      end
      local count = 0
      for _, mark in ipairs(marks) do
        local lnum = mark:lnum()
        local hl = lnum and require('org.files').get_buffer(bufnr):headline_on(lnum)
        if hl then
          -- archive_subtree returns nothing and silently keeps the subtree
          -- when its write fails, so the only honest signal is the source
          -- buffer: a subtree that left it took its lines with it.
          local before = vim.api.nvim_buf_line_count(bufnr)
          require('org.archive').archive_subtree({ bufnr = bufnr, lnum = hl.line })
          if vim.api.nvim_buf_line_count(bufnr) < before then
            count = count + 1
          end
        end
      end
      return count
    end)
  end)

  if moved == 0 then
    notify('org roll: nothing moved (the archive file could not be written)')
    return
  end

  -- archive_subtree saves the archive file but never the source: it edits the
  -- board buffer and leaves it modified, which a per-subtree key can live with
  -- and a batch sweep cannot (a `${board}.org` still holding the rolled tickets
  -- on disk while the buffer shows them gone is a trap). Save it here.
  require('org.utils').save_buffer_or_warn(bufnr)

  local msg = string.format('🤖 rolled %d %s ticket%s → %s', moved, what, moved == 1 and '' or 's', vim.fn.fnamemodify(archive, ':~'))
  if #flagged > 0 then
    local shown = vim.list_slice(flagged, 1, 3)
    msg = msg .. string.format(
      '\n   %d with a body over %d lines and no KB link: %s%s',
      #flagged,
      BIG_ENTRY_LINES,
      table.concat(shown, ' · '),
      #flagged > #shown and ' …' or ''
    )
  end
  notify(msg)
end

--- `<leader>oD`: roll every finished ticket off this board.
function M.roll()
  sweep(function(hl)
    return not has_open_todo(hl)
  end, 'finished')
end

--- `<leader>oA`: the same, but only what closed more than GRACE_DAYS ago.
function M.roll_aged()
  sweep(function(hl)
    return not has_open_todo(hl) and closed_before(hl, GRACE_DAYS)
  end, string.format('closed over %d days ago', GRACE_DAYS))
end

--- `<leader>oU`: move the entry at point back into its board, under the parent
--- whose outline path the archive drawer recorded. `ARCHIVE_FILE` and
--- `ARCHIVE_OLPATH` are the whole reason the drawer exists, and they make the
--- move reversible -- org.nvim has no other un-archive.
function M.unarchive()
  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local hl = require('org.files').get_buffer(bufnr):headline_on(lnum)
  if not hl then
    notify('org roll: not under a headline', vim.log.levels.WARN)
    return
  end

  local board = hl:get_property('ARCHIVE_FILE', false)
  local olpath = hl:get_property('ARCHIVE_OLPATH', false)
  local was = hl:get_property('ARCHIVE_TODO', false)
  if not (board and board:match '%S') then
    notify('org roll: no :ARCHIVE_FILE: here -- not an archived entry', vim.log.levels.WARN)
    return
  end

  local dest = vim.fn.expand(board)
  if not vim.uv.fs_stat(dest) then
    notify('org roll: ' .. dest .. ' is gone', vim.log.levels.WARN)
    return
  end

  local dbuf = require('org.utils').load_buffer(dest)
  local dfile = require('org.files').get_buffer(dbuf)
  local parent
  for _, h in ipairs(dfile.headlines) do
    -- :ARCHIVE_OLPATH: is the archived entry's ancestor path, so the headline
    -- to put it back under is the one whose *own* path equals it. Note
    -- Headline:outline_path() walks parents only -- it excludes the headline
    -- itself -- so the candidate's own path is its outline path plus its title.
    local own = h:outline_path()
    own[#own + 1] = h:plain_title()
    if table.concat(own, '/') == (olpath or '') then
      parent = h
      break
    end
  end
  if not parent then
    notify(string.format('org roll: %s has no "%s" headline to put this under', vim.fn.fnamemodify(dest, ':t'), olpath or ''), vim.log.levels.WARN)
    return
  end

  local title = hl:plain_title()
  local _, dlnum = require('org.refile').move({ bufnr = bufnr, lnum = hl.line }, { bufnr = dbuf, lnum = parent.line })
  for _, name in ipairs { 'ARCHIVE_TIME', 'ARCHIVE_FILE', 'ARCHIVE_OLPATH', 'ARCHIVE_CATEGORY', 'ARCHIVE_TODO', 'ARCHIVE_ITAGS', 'ARCHIVE_OLID' } do
    pcall(require('org.properties').delete_property, { bufnr = dbuf, lnum = dlnum }, name)
  end
  if was and was:match '%S' and was ~= 'DONE' then
    pcall(require('org.todo').change_state, { bufnr = dbuf, lnum = dlnum }, was, { force = true })
  end
  -- the parent's [n/m] cookie: archiving updated it on the way out, so the way
  -- back has to as well
  pcall(require('org.lists').update_statistics_for, dbuf, parent.line)

  local utils = require('org.utils')
  utils.save_buffer_or_warn(dbuf)
  utils.save_buffer_or_warn(bufnr)
  notify(string.format('🤖 un-archived “%s” → %s · %s', title, vim.fn.fnamemodify(dest, ':t'), olpath or ''))
end

return M
