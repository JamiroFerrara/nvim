-- Statistics-cookie maintenance for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): automatic `[/]` / `[x/y]` cookies, the
-- auto-DONE when an entry's checkboxes are all checked, and the undo hygiene
-- that keeps both out of the user's undo history.
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
  local fresh = vim.fn.undotree().seq_cur == 0
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

local function schedule_cookies(bufnr)
  if updating or queued[bufnr] then
    return
  end
  queued[bufnr] = true
  vim.defer_fn(function()
    queued[bufnr] = nil
    ensure_cookies(bufnr)
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
    end
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
