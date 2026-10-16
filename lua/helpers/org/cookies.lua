-- Statistics-cookie maintenance for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): automatic `[/]` / `[x/y]` cookies, the
-- auto-DONE when an entry's checkboxes are all checked, the auto-DONE of an
-- entry whose child headlines are all finished, the reopen of a finished
-- entry that gains an open child (a capture or a typed subtree), and the
-- undo hygiene that keeps all of it out of the user's undo history.
--
-- `M.ensure` is the one entry point outside them: the pass above runs for a
-- buffer that is loaded and on screen, and a checkbox toggled from a TODO
-- view (helpers/org/tree.lua) edits a file no window shows, so the view asks
-- for the cookies itself before the box is counted.
local M = {}

local updating = false
local queued = {}

--- Statistics cookies and checkbox->DONE are bookkeeping, not user edits. A
--- normal write would add its own undo step, so `u` after deleting an item
--- undid the counter refresh instead of the deletion, and the refresh
--- autocmds put it right back (a loop). `:undojoin` folds the write into the
--- change that triggered it, so `u` undoes that change together with its
--- counter update and no separate step appears. (Do NOT use
--- undolevels = -1 here: changing 'undolevels' clears the undo history.)
local function joined(fn)
  return function(bufnr, ...)
    pcall(vim.cmd, 'silent! undojoin')
    return fn(bufnr, ...)
  end
end

--- Checking the last checkbox of an entry finishes it: an entry whose own
--- section's checkboxes are all checked and that still carries a non-DONE
--- TODO keyword is moved to its sequence's first DONE keyword. Emacs leaves
--- that to the user; here it rides on lists.update_checkbox_count_maybe,
--- which every checkbox toggle ends with (C-c C-c, <CR> on an item,
--- C-c C-x C-b and the headline/Visual forms of it,
--- reset-checkbox-state-subtree, list item edits), so the entry closes on
--- the same keystroke that checked the last box. It is never triggered by
--- loading a file: that path calls update_statistics_for directly, not
--- update_checkbox_count_maybe, so opening an all-checked entry leaves its
--- keyword alone.
local function finish_when_boxes_done(bufnr, lnum)
  local lists = require 'org.lists'
  local file = require('org.files').get_buffer(bufnr)
  local hl = file and file:headline_at(lnum)
  if not hl or not hl.todo or file.settings.todo:is_done(hl.todo) then
    return
  end
  local _, all = lists.parse_region(file.lines, hl.line + 1, hl.body_end)
  local total, checked = 0, 0
  for _, it in ipairs(all) do
    if it.checkbox then
      total = total + 1
      if it.checkbox == 'X' then
        checked = checked + 1
      end
    end
  end
  if total == 0 or checked < total then
    return
  end
  local target = file.settings.todo:first_done(hl.todo)
  if target then
    pcall(vim.cmd, 'silent! undojoin')
    require('org.todo').change_state({ bufnr = bufnr, lnum = hl.line }, target)
  end
end

--- Keywords this vault treats as finished besides the org DONE ones. The
--- vocabulary is `TODO NEXT PEND TEST WARN | DONE` (lua/terminal_plugins/
--- org.nvim.lua): an entry is over in TEST (work done, awaiting validation)
--- or WARN (could not complete) too, but both sit before the `|`, so
--- org.todo_keywords reports neither as done.
local FINISHED = { TEST = true, WARN = true }

--- Is `name` a keyword that means the entry is over?
local function finished_p(kw, name)
  return name ~= nil and (kw:is_done(name) or FINISHED[name] == true)
end

--- Does `hl` have a direct child entry that is still open (carries a TODO
--- keyword that is neither org-done nor a vault-finished one)?
local function open_child(hl, kw)
  for _, c in ipairs(hl.children or {}) do
    if c.todo and not finished_p(kw, c.todo) then
      return true
    end
  end
  return false
end

--- Are all of `hl`'s direct child entries over? A child without a TODO
--- keyword does not count -- there is nothing to finish -- so an entry with
--- no keyworded child at all is not "all done": there was nothing to close.
local function children_done(hl, kw)
  local n = 0
  for _, c in ipairs(hl.children or {}) do
    if c.todo then
      if not finished_p(kw, c.todo) then
        return false
      end
      n = n + 1
    end
  end
  return n > 0
end

--- A new open entry reopens a finished parent: an entry with an open child
--- is not over, so it goes back to the first open keyword of its sequence
--- (TODO). Emacs leaves this to the user; here it is called only where an
--- entry can appear -- with `lnum`, for the ancestors of a single entry a
--- capture just stored (a programmatic capture writes the target buffer
--- directly, org.capture.session.store, so the debounced TextChanged pass
--- never sees the new entry); without it, over every headline of the
--- buffer, from that same debounced pass (schedule_cookies) so a typed
--- subtree gets the same treatment. It is deliberately absent from
--- ensure_cookies: OrgFileLoaded and OrgTodoStateChange call that alone, so
--- opening a file changes nothing and a state the user set by hand (or the
--- checkbox auto-DONE) is not fought on the spot.
---@param lnum? integer entry whose ancestors to check (nil: every headline)
local function reopen_finished(bufnr, lnum)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= 'org' then
    return
  end
  local files = require 'org.files'
  local todo = require 'org.todo'
  local file = files.get_buffer(bufnr)
  local kw = file and file.settings.todo
  if not kw then
    return
  end
  local targets = {}
  if lnum then
    local hl = file:headline_at(lnum)
    -- only an open stored entry means an open child just appeared
    if not (hl and hl.todo and not finished_p(kw, hl.todo)) then
      return
    end
    local parent = hl.parent
    while parent do
      if finished_p(kw, parent.todo) and open_child(parent, kw) then
        targets[#targets + 1] = parent.line
      end
      parent = parent.parent
    end
  else
    for _, hl in ipairs(file.headlines) do
      if finished_p(kw, hl.todo) and open_child(hl, kw) then
        targets[#targets + 1] = hl.line
      end
    end
  end
  for _, line in ipairs(targets) do
    local p = files.get_buffer(bufnr):headline_at(line)
    if p and finished_p(kw, p.todo) and open_child(p, kw) then
      pcall(vim.cmd, 'silent! undojoin')
      todo.change_state({ bufnr = bufnr, lnum = line }, kw:first_todo(kw:get(p.todo).seq))
    end
  end
end

--- The last child of an entry being finished finishes the entry: a headline
--- that carries a live TODO keyword and whose child headlines are all over
--- moves to its sequence's first DONE keyword -- the mirror of
--- reopen_finished, so an entry is over exactly while its children are. It
--- cascades: the change it makes fires OrgTodoStateChange again, which runs
--- it on the entry's own ancestors, closing an all-done subtree to the top.
--- Called only from that event, so opening a file or a hand-set state is
--- never fought (the same reason reopen_finished is absent from
--- ensure_cookies).
---@param bufnr integer
---@param lnum integer the entry that just changed
local function finish_when_children_done(bufnr, lnum)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= 'org' then
    return
  end
  local files = require 'org.files'
  local todo = require 'org.todo'
  local file = files.get_buffer(bufnr)
  local kw = file and file.settings.todo
  if not kw then
    return
  end
  local hl = lnum and file:headline_at(lnum)
  if not hl then
    return
  end
  local targets = {}
  local parent = hl.parent
  while parent do
    if parent.todo and not finished_p(kw, parent.todo) and children_done(parent, kw) then
      targets[#targets + 1] = parent.line
    end
    parent = parent.parent
  end
  for _, line in ipairs(targets) do
    local p = files.get_buffer(bufnr):headline_at(line)
    if p and p.todo and not finished_p(kw, p.todo) and children_done(p, kw) then
      local target = kw:first_done(p.todo)
      if target then
        pcall(vim.cmd, 'silent! undojoin')
        todo.change_state({ bufnr = bufnr, lnum = line }, target)
      end
    end
  end
end

--- Automatic statistics cookies. Emacs and org.nvim only keep a `[/]` /
--- `[x/y]` cookie up to date if it is already there (org.lists
--- update_section rewrites only lines with a cookie); nothing inserts one.
--- Here a `[/]` is added to every headline whose child entries have TODO
--- keywords, or whose own section has checkboxes, and org.nvim then
--- maintains the numbers. Runs when a file is parsed, on TODO state changes
--- and shortly after edits (debounced).
local function ensure_cookies(bufnr)
  if updating or not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= 'org' then
    return
  end
  updating = true
  -- Freshly loaded buffer: nothing to merge into, and the history is empty,
  -- so write with undo disabled -- opening a file must not add an undo step.
  -- Later passes merge into the change that triggered them via `:undojoin`
  -- (see `joined`); they must NOT touch 'undolevels', which would discard
  -- the user's undo steps.
  -- queried on `bufnr`: ensure_cookies also runs for a capture target, a
  -- buffer that is not the current one (undotree() would read the agenda's)
  local fresh
  if bufnr == vim.api.nvim_get_current_buf() then
    fresh = vim.fn.undotree().seq_cur == 0
  else
    local ok, seq = pcall(vim.api.nvim_buf_call, bufnr, function()
      return vim.fn.undotree().seq_cur
    end)
    fresh = ok and seq == 0
  end
  local saved_ul
  if fresh then
    saved_ul = vim.bo[bufnr].undolevels
    vim.bo[bufnr].undolevels = -1
  else
    pcall(vim.cmd, 'silent! undojoin')
  end
  local ok, err = pcall(function()
    local files = require 'org.files'
    local lists = require 'org.lists'
    local parser = require 'org.parser'
    local edit = require 'org.edit'
    local file = files.get_buffer(bufnr)
    local last = vim.api.nvim_buf_line_count(bufnr)
    for _, hl in ipairs(file.headlines) do
      if hl.line <= last and hl.raw:find '%[%d*[/%%]%d*%]' then
        -- an existing (possibly bare `[/]`) cookie: fill it in
        lists.update_statistics_for(bufnr, hl.line)
      elseif hl.line <= last then
        -- only parse the section when it could hold a checkbox
        local maybe_box = false
        for i = hl.line + 1, math.min(hl.body_end, last) do
          if file.lines[i]:find '[%[%]]' then
            maybe_box = true
            break
          end
        end
        local has_box = false
        if maybe_box then
          for _, l in ipairs(lists.parse_region(file.lines, hl.line + 1, hl.body_end)) do
            for _, it in ipairs(l.items) do
              if it.checkbox then
                has_box = true
              end
            end
          end
        end
        local want = has_box or select(2, lists.todo_counts(file, hl)) > 0
        if want then
          local p = parser.parse_headline_line(hl.raw, file.settings.todo)
          if p then
            edit.update_headline(bufnr, hl.line, { title = (p.title or '') .. ' [/]' })
            lists.update_statistics_for(bufnr, hl.line)
            file = files.get_buffer(bufnr)
          end
        end
      end
    end
  end)
  if saved_ul then
    vim.bo[bufnr].undolevels = saved_ul
  end
  updating = false
  if not ok then
    require('org.utils').warn('statistics cookies: ' .. tostring(err))
  end
end

--- Add the statistics cookies `bufnr` is missing, the way opening the file
--- on screen does: a checkbox toggled from outside the buffer (from a TODO
--- view, helpers/org/tree.lua) must leave the entry counted even when no
--- buffer ever showed it, and a programmatic edit raises no TextChanged for
--- the debounced pass to ride on.
---@param bufnr integer
function M.ensure(bufnr)
  ensure_cookies(bufnr)
end

local function schedule_cookies(bufnr)
  if updating or queued[bufnr] then
    return
  end
  queued[bufnr] = true
  vim.defer_fn(function()
    queued[bufnr] = nil
    ensure_cookies(bufnr)
    -- a typed subtree reaches the reopen only here; OrgTodoStateChange and
    -- OrgFileLoaded call ensure_cookies alone, so a state the user set by
    -- hand (or the checkbox auto-DONE) is not fought
    reopen_finished(bufnr)
  end, 300)
end

function M.setup()
  -- The statistics/checkbox wrappers and the event listeners plug into
  -- org.lists and org.api; both load on first use, so they go through
  -- org.lazy.on_load and neither is required at startup. The hook runs
  -- while the module is being required, before any caller can use it.
  require('org.lazy').on_load('org.lists', 'statistics_hooks', function(lists)
    lists.update_statistics_for = joined(lists.update_statistics_for)
    lists.update_statistics = joined(lists.update_statistics)
    lists.update_all_statistics = joined(lists.update_all_statistics)

    local update_checkbox_count_maybe = lists.update_checkbox_count_maybe
    lists.update_checkbox_count_maybe = function(bufnr, lnum)
      update_checkbox_count_maybe(bufnr, lnum)
      finish_when_boxes_done(bufnr, lnum)
    end
  end)

  -- org's events are plain User autocmds (org.api.on is exactly this), so
  -- they are created directly: requiring org.api here just to call it would
  -- load a module the plugin never needs itself, and org.files only fires
  -- OrgFileLoaded when it finds a listener.
  local function on_event(event, fn)
    vim.api.nvim_create_autocmd('User', {
      pattern = event,
      desc = 'cookies: ' .. event,
      callback = function(ev)
        fn(ev.data or {}, ev)
      end,
    })
  end

  on_event('OrgFileLoaded', function(data)
    -- only buffers on screen: a hidden buffer loaded as a refile/capture
    -- target (e.g. refile.org while a capture is stored and refiled out
    -- again) would get a cookie for a state that no longer holds
    if data.bufnr and vim.fn.bufwinid(data.bufnr) ~= -1 then
      vim.schedule(function()
        ensure_cookies(data.bufnr)
      end)
    end
  end)
  on_event('OrgTodoStateChange', function(data)
    if data.bufnr then
      ensure_cookies(data.bufnr)
      -- finishing the last open child finishes the parent (cascades up);
      -- a reopen (data.done false) is the other direction, handled below
      if data.done and data.lnum then
        finish_when_children_done(data.bufnr, data.lnum)
      end
    end
  end)
  -- A capture stores its entry programmatically and saves the target before
  -- this event fires, so nothing else refreshes the target: no TextChanged
  -- (nvim_buf_set_lines raises none) and no OrgFileLoaded (the listener
  -- above skips a buffer that is not on screen, which a capture target
  -- loaded hidden is). Reopen a finished parent the new open entry sits
  -- under and give the parent its statistics cookie, then save -- the store
  -- already wrote the file, but these edits come after it. Registered before
  -- the agenda's own OrgCaptureAfterFinalize listener (helpers/org/agenda.lua
  -- setup_capture_refresh, the setup order in lua/terminal_plugins/org.nvim.lua)
  -- so the view it re-renders reflects both.
  on_event('OrgCaptureAfterFinalize', function(data)
    if not (data.bufnr and data.line) then
      return
    end
    reopen_finished(data.bufnr, data.line)
    ensure_cookies(data.bufnr)
    require('org.utils').save_buffer(data.bufnr)
  end)

  vim.api.nvim_create_user_command('OrgEnsureCookies', function()
    ensure_cookies(vim.api.nvim_get_current_buf())
  end, { desc = 'Add missing TODO/checkbox statistics cookies' })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
    callback = function(args)
      if vim.bo[args.buf].filetype == 'org' then
        schedule_cookies(args.buf)
      end
    end,
  })
end

return M
