-- Agenda-side customizations for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): the `D` toggle_done action, the
-- one-key tag/priority toggles (helpers/org/tagging.lua), the fold state
-- left behind by entering an entry, the insert mode a terminal window would
-- otherwise leave in the agenda, the re-render after a capture filed from
-- it, and the 1..4 switch between the custom views of
-- agenda.custom_commands. All of them plug into modules
-- the plugin loads on first use, so they go through org.lazy.on_load and
-- nothing here is required at startup.
--
-- The agenda opens in the focused window (agenda.window = 'current' in the
-- plugin spec), so there is no split to unwrap on open and `q` puts the
-- previous buffer back (view/window.lua, mode "current").
local M = {}

-- `D` in the agenda toggles an entry between DONE and TODO: a done entry
-- goes back to TODO, anything else (open, or no keyword at all) becomes
-- DONE. change_state runs the full org semantics (CLOSED timestamp, state
-- logging, blockers, repeaters). The agenda mapping table only addresses
-- actions by name, so the action is added to the agenda action table
-- (org.agenda.view.actions); the `mappings.agenda.toggle_done = 'D'` in the
-- plugin spec points `D` at it. The hook runs inside `require
-- 'org.agenda.view'`, before view.open builds the agenda mappings from that
-- table.
local function setup_toggle_done()
  require('org.lazy').on_load('org.agenda.view', 'toggle_done', function(view)
    view.actions.toggle_done = view.on_item(function(target)
      local bufnr, file, hl = require('org.edit').resolve_headline(target)
      if not bufnr then
        return
      end
      local done = file.settings.todo:is_done(hl.todo)
      return require('org.todo').change_state({ bufnr = bufnr, lnum = hl.line }, done and 'TODO' or 'DONE')
    end, 'lines')
  end)
end

-- One-key tagging and priorities (helpers/org/tagging.lua): the plain
-- B/F/C toggle :bug:/:feat:/:chore: and <M-a>/<M-b>/<M-c> the A/B/C
-- priority on the entry at point. Every toggle is registered as an agenda
-- action named in the specs' `action` field, and `mappings.agenda` in the
-- plugin spec binds it -- the way toggle_done above does; the plain B / F /
-- C defaults (bulk action, follow mode, clock report) are reassigned there
-- to make room. The hook runs inside `require 'org.agenda.view'`, before
-- view.open builds the agenda mappings from that table.
local function setup_one_key()
  require('org.lazy').on_load('org.agenda.view', 'one_key', function(view)
    local tagging = require 'helpers.org.tagging'
    for _, spec in ipairs(tagging.tags) do
      local tag = spec.tag
      view.actions[spec.action] = view.on_item(function(target)
        return tagging.toggle_tag(tag, target)
      end, 'lines')
    end
    for _, spec in ipairs(tagging.priorities) do
      local value = spec.value
      view.actions[spec.action] = view.on_item(function(target)
        return tagging.toggle_priority(value, target)
      end, 'lines')
    end
  end)
end

-- Entering an entry from the list (RET = switch_to, <Tab> = goto) lands in
-- the entry's file, in whatever fold state the buffer was last left in: the
-- #+STARTUP rule is applied when a buffer is loaded, not when it is shown
-- again, and a file open unfolded in another window stays unfolded here.
-- helpers/org/folding.lua show_jump_target re-applies the rule and unfolds
-- the entered tree; the wrappers below run it after the jump. The action
-- table is read when the agenda mappings are built, so both are wrapped the
-- way toggle_done is registered above.
local function setup_entry_folds()
  require('org.lazy').on_load('org.agenda.view', 'entry_folds', function(view)
    for _, name in ipairs { 'switch_to', 'goto' } do
      local action = view.actions[name]
      if action then
        view.actions[name] = function(...)
          local result = action(...)
          require('helpers.org.folding').show_jump_target()
          return result
        end
      end
    end
  end)
end

-- The agenda -- and the TODO view, which renders into the same buffer -- is
-- read-only, so it must be in Normal mode: anything that lands insert or
-- terminal mode in it is left again. Two ways it lands:
--   * launching from a terminal window: the terminal's autocommands
--     (autocommands.lua: TermOpen / FocusGained / BufEnter term://*) call
--     startinsert, and it applies to the agenda buffer right after it is
--     set (logged: FileType orgagenda, then InsertEnter buftype=nofile
--     name=agenda);
--   * coming back to it: a window switch out of a capture (still in insert
--     mode, helpers/org/mappings.lua) or a tmux pane switch bringing the
--     focus back re-enters the view with the mode it had.
-- The rules are buffer-local, so they die with the view. `agenda.window =
-- 'current'` means the view takes over the window it was opened in, so the
-- current buffer right after open is the agenda one. The wrapper is
-- installed when org.agenda first loads (the agenda command requiring it),
-- which is before any of its functions run.
-- A TODO-style view lists entries (a `todo`, `tags_todo`, `search`, ... block);
-- an agenda view draws the day grid, and there the cursor belongs on today's
-- header (org.nvim's own rule). The difference is the block type.
local function is_todo_view(view)
  if not view then
    return false
  end
  for _, block in ipairs(view.blocks or { view }) do
    if block.type == 'agenda' then
      return false
    end
  end
  return true
end

-- org.nvim puts the cursor on the first item of a TODO list when it opens one
-- (view/window.lua: today's header in agenda views, else the first item), but
-- that placement is a pcall'd best effort and the buffer is reused: a view
-- opened while the previous one is still on screen, or one refreshed by a
-- capture or by the AI sync (helpers/org/ai.lua), can leave the cursor off the
-- entries. Re-assert "first item" on every entry into a TODO-style view -- on
-- an agenda view it does nothing, so today's header stays.
local function focus_first_item(buf)
  local view = require 'org.agenda.view'
  local state = view.state_of(buf)
  if not (state and is_todo_view(state.view)) then
    return
  end
  local items = state.line_items or {}
  if items[vim.api.nvim_win_get_cursor(0)[1]] then
    return
  end
  local lines = vim.tbl_keys(items)
  table.sort(lines)
  if lines[1] then
    pcall(vim.api.nvim_win_set_cursor, 0, { lines[1], 0 })
  end
end

local function setup_open()
  require('org.lazy').on_load('org.agenda', 'window_setup', function(agenda)
    local agenda_open = agenda.open
    -- org.nvim reuses one agenda buffer (org://agenda, bufhidden=hide), so
    -- the rules go on once per buffer, not once per open.
    local guarded = {}
    agenda.open = function(spec, opts)
      local ok, err = pcall(agenda_open, spec, opts)
      if not ok then
        error(err)
      end
      local buf = vim.api.nvim_get_current_buf()
      focus_first_item(buf)
      local function normal_mode()
        if vim.api.nvim_get_current_buf() ~= buf then
          return
        end
        local mode = vim.api.nvim_get_mode().mode
        if mode == 't' then
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true), 'n', false)
        elseif mode:sub(1, 1) == 'i' then
          pcall(vim.cmd, 'stopinsert')
        end
      end
      normal_mode()
      if guarded[buf] then
        return
      end
      guarded[buf] = true
      vim.api.nvim_create_autocmd('InsertEnter', {
        buffer = buf,
        -- stopinsert during InsertEnter does not take; leave after
        callback = function()
          vim.defer_fn(normal_mode, 0)
        end,
        desc = 'org: leave insert mode in the agenda',
      })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
        buffer = buf,
        callback = function()
          vim.defer_fn(normal_mode, 0)
          vim.defer_fn(function()
            focus_first_item(buf)
          end, 0)
        end,
        desc = 'org: leave insert mode / first item when landing on the agenda',
      })
    end
  end)
end

-- Number keys open the custom views configured in
-- lua/terminal_plugins/org.nvim.lua (agenda.custom_commands): 1 all open
-- TODOs across every project, 2 the sectioned board (bugs, WARN, features,
-- done), 3 priorities, 4 chores. Buffer-local to orgagenda -- the TODO view
-- renders into the same buffer, so it switches from there too -- which is
-- why the keys are the plain digits and not the `<leader>o` ones: a count
-- typed in the agenda (`<C-u>` style) no longer starts with 1 or 2, and
-- nothing else claims them. `agenda.window = 'current'` makes the open take
-- the window over, so the same buffer is refilled and this reads as
-- switching view rather than stacking a second agenda.
--
-- The 2 / 3 / 4 views are scoped to the project of the working directory,
-- the way `°` is for the TODO view (helpers/org/project.lua): each block's
-- `files` becomes the project's file and a headline claim adds its subtree
-- restriction. A cwd that names no project -- or one whose file does not
-- exist yet -- opens the full view, the same one the dispatcher menu's
-- `w` / `p` / `c` give. Resolution runs per key press (project.current reads
-- getcwd, or the job cwd of a terminal buffer), so a `cd` moves the scope
-- with it. 1 is global: it never scopes, so it lists the open TODOs of every
-- project.
local CUSTOM_VIEWS = {
  { '1', 'o', 'all open TODOs', true },
  { '2', 'w', 'bugs, features and done' },
  { '3', 'p', 'open A/B priorities' },
  { '4', 'c', 'open chores' },
}

-- The group headers the custom views draw: the global super_agenda groups
-- (lua/terminal_plugins/org.nvim.lua) with `auto_category` swapped for a
-- title group, so the entries are headed by the project file's title (the
-- "Nvim" of "Nvim [30/35]") instead of "Category: nvim". Scoped to one
-- project the group becomes a nameless catch-all (an empty section name
-- draws no header, and every item still lands in a section, so the "Other
-- items" heading does not appear either): the category is the same under
-- every section -- "Category: nvim" repeated in each of Bugs, WARN,
-- Features and Done -- and each block header already names the title
-- ("Nvim - Bugs, open"). The list is read and copied at open time, so the
-- agenda's own groups -- the day view keeps the globals -- are untouched.
local function view_groups(scoped)
  local project = require 'helpers.org.project'
  local out = {}
  for _, group in ipairs(require('org.extensions').opts('super_agenda').groups or {}) do
    if group.auto_category then
      local replacement = vim.deepcopy(group)
      replacement.auto_category = nil
      if scoped then
        replacement.auto_map = function()
          return ''
        end
      else
        replacement.auto_map = function(item)
          return item.filename and project.file_title(item.filename) or nil
        end
      end
      out[#out + 1] = replacement
    else
      out[#out + 1] = vim.deepcopy(group)
    end
  end
  return out
end

local function open_custom_view(key, label, global)
  local command = (require('org.config').opts.agenda.custom_commands or {})[key]
  if not command then
    require('org.utils').warn('agenda: no custom command ' .. key)
    return
  end
  local spec, opts = vim.deepcopy(command), nil
  local project = require 'helpers.org.project'
  local current = not global and project.current() or nil
  local scoped = current ~= nil and vim.uv.fs_stat(current.file) ~= nil
  local groups = view_groups(scoped)
  local title, files
  if scoped then
    title = project.title(current)
    files = project.files(current)
  end
  for _, block in ipairs(spec.types or { spec }) do
    block.super_groups = groups
    if scoped then
      block.files = files
      -- the block header is drawn (view.title is not), so the project name
      -- goes there: an empty view -- a project with no bug, say -- still
      -- says what it filtered on instead of looking broken
      block.header = block.header and (title .. ' - ' .. block.header) or title
    end
  end
  if scoped then
    local restrict = project.restrict(current)
    if restrict then
      opts = { restrict = restrict }
    end
  end
  require('org.utils').run(function()
    require('org.agenda').open(spec, opts)
  end)
end

local function setup_custom_views()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'orgagenda',
    callback = function(args)
      for _, view in ipairs(CUSTOM_VIEWS) do
        local key, command, label, global = view[1], view[2], view[3], view[4]
        vim.keymap.set('n', key, function()
          open_custom_view(command, label, global)
        end, { buffer = args.buf, desc = 'org: Agenda view ' .. key .. ' (' .. label .. ')' })
      end
    end,
  })
end

-- <leader>ai on an entry launches an `omp` instance for that ticket in a
-- tmux pane (helpers/org/ai.lua), shadowing the global plain-omp terminal
-- key in the agenda and in the TODO view, which renders into the same
-- buffer. Buffer-local, so it lands after org.nvim's own mappings.
local function setup_ai()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'orgagenda',
    callback = function(args)
      vim.keymap.set('n', '<leader>ai', function()
        require('helpers.org.ai').launch()
      end, { buffer = args.buf, desc = 'org: OMP on the ticket at point' })
    end,
  })
end

-- A capture started from the agenda or the TODO view (`^` there, the global
-- capture key, is left free by agenda.filter_top_headline = false) leaves
-- the list showing what it showed before the new entry existed: org.nvim
-- stores the entry and fires OrgCaptureAfterFinalize, but never re-renders
-- the agenda, and the view is only rebuilt on `r` or when it is opened
-- again. Finish the capture and put the view back on screen instead --
-- close_session restores the window the capture was started from, so the
-- current buffer here is the orgagenda one -- and re-render it. The User
-- autocmd is global but the callback leaves every other capture (a normal
-- org buffer's) alone; the view module is required only when it fires.
local function setup_capture_refresh()
  vim.api.nvim_create_autocmd('User', {
    pattern = 'OrgCaptureAfterFinalize',
    callback = function(args)
      if args.data and args.data.aborted then
        return
      end
      if vim.bo[vim.api.nvim_get_current_buf()].filetype ~= 'orgagenda' then
        return
      end
      require('org.agenda.view').refresh()
    end,
    desc = 'org: re-render the agenda after a capture filed from it',
  })
end

function M.setup()
  setup_toggle_done()
  setup_one_key()
  setup_entry_folds()
  setup_open()
  setup_custom_views()
  setup_capture_refresh()
  setup_ai()
end

return M
