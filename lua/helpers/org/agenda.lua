-- Agenda-side customizations for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): the `D` toggle_done action, the
-- one-key tag/priority toggles (helpers/org/tagging.lua), the fold state
-- left behind by entering an entry, the insert mode a terminal window would
-- otherwise leave in the agenda, the re-render after a capture filed from
-- it (with the subtree range of a headline project's `°` view kept in step,
-- else the entry it just wrote falls outside it), and the 1..3 switch
-- between the custom views of
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
-- TODOs across every project, 2 the sectioned board (bugs, features,
-- untagged, done), 3 priorities. Buffer-local to orgagenda -- the TODO view
-- renders into the same buffer, so it switches from there too -- which
-- is why the keys are the plain digits and not the `<leader>o` ones: a count
-- typed in the agenda (`<C-u>` style) no longer starts with 1 or 2, and
-- nothing else claims them. `agenda.window = 'current'` makes the open take
-- the window over, so the same buffer is refilled and this reads as
-- switching view rather than stacking a second agenda.
--
-- The 2 / 3 views are scoped to the project of the working directory, the
-- way `°` is (helpers/org/project.lua, which opens the `w` board directly
-- through M.custom_view): each block's `files` becomes the project's file
-- and a headline claim adds its subtree restriction. A cwd that names no
-- project -- or one whose file does not exist yet -- opens the full view,
-- the same one the dispatcher menu's `w` / `p` give. Resolution runs per key
-- press (project.current reads getcwd, or the job cwd of a terminal buffer),
-- so a `cd` moves the scope with it. 1 is global: it never scopes, so it
-- lists the open TODOs of every project.
local CUSTOM_VIEWS = {
  { '1', 'o', 'all open TODOs', true },
  { '2', 'w', 'bugs, features, untagged and done' },
  { '3', 'p', 'open A/B priorities' },
}

-- The group headers the custom views draw: the global super_agenda groups
-- (lua/terminal_plugins/org.nvim.lua) with `auto_category` swapped for a
-- title group, so the entries are headed by the project file's title (the
-- "Nvim" of "Nvim [30/35]") instead of "Category: nvim". Scoped to one
-- project the group becomes a nameless catch-all (an empty section name
-- draws no header, and every item still lands in a section, so the "Other
-- items" heading does not appear either): the category is the same under
-- every section -- "Category: nvim" repeated -- and each block header
-- already names the title ("Nvim - Bugs, open"). A block that brings its
-- own `super_groups` -- the board's Bugs / Features / Untagged sections,
-- which split by state -- keeps them (open_custom_view below). The list is
-- read and copied at open time, so the agenda's own groups -- the day view
-- keeps the globals -- are untouched.
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
    -- a block with its own groups keeps them; the board's state sections
    -- set them in the config, and its flat Done section opts out with
    -- `super_groups = false` (org-super-agenda leaves such a block ungrouped)
    if block.super_groups == nil then
      block.super_groups = groups
    end
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

--- Open a `custom_commands` view by its key, the same the agenda buffer's
--- number keys run (helpers.org.project.todo_view opens the `w` board this
--- way). Scoped to the cwd's project like the `2` / `3` keys; `global`
--- (`1`) skips the scope. The `label` the keymaps pass is only their `desc`,
--- so the key stands in for it.
---@param key string a key of agenda.custom_commands
---@param global boolean|nil list every agenda file instead of the project
function M.custom_view(key, global)
  open_custom_view(key, key, global)
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

-- A full-width `─` rule line, what the extension's `add_separator` draws for
-- a one-character `header_separator`. It splices a line into the builder at
-- `pos` (1-based, before the line already there) and shifts the line-indexed
-- tables the builder carries with it -- the highlight rows (0-based), the
-- `items` / `line_hls` / `line_ctx` / `entry_text_lines` / `day_lines` /
-- `super_headers` maps keyed by line, and `block_starts` (render.view) -- so
-- the block that already wrote its header keeps it. Used for the board's
-- Done section, which carries `rule_above`.
local function insert_rule(b, pos, width)
  local text = string.rep('─', math.max((width or 80) - 1, 10))
  table.insert(b.lines, pos, text)
  for _, h in ipairs(b.hls) do
    if h[1] >= pos - 1 then
      h[1] = h[1] + 1
    end
  end
  b.hls[#b.hls + 1] = { pos - 1, 0, #text, 'OrgSuperAgendaSeparator' }
  for _, key in ipairs { 'items', 'line_hls', 'line_ctx', 'entry_text_lines', 'day_lines', 'super_headers' } do
    local t = b[key]
    if t then
      local moved = {}
      for k, v in pairs(t) do
        moved[k >= pos and k + 1 or k] = v
      end
      b[key] = moved
    end
  end
  for i, s in ipairs(b.block_starts or {}) do
    if s >= pos then
      b.block_starts[i] = s + 1
    end
  end
end

-- The board's state sections want a rule between them ("WARN", a line,
-- the entries), not the blank line the extension's `header_separator`
-- gives every group, and a blank line after the section, not another rule.
-- Both are options for the whole extension, so they are swapped around the
-- render of a block that carries `state_sections` (set in the config with
-- the block's `super_groups`), and put back whatever the render did. A block
-- marked `hide_empty` with nothing in it is dropped instead: the header
-- `insert_header` already wrote is taken back off the builder (with its
-- `block_starts` entry), and the grouper reports the block rendered so
-- the (empty) list is not drawn under nothing. A block marked `rule_above`
-- gets a `─` rule on the line before its header (insert_rule), which is how
-- the board sets the Done section apart from the open ones. This wraps the
-- grouper super_agenda installs through its own on_load for the same module,
-- so it must run after it: on_load runs a module's hooks sorted by key, and
-- the key here sorts after super_agenda's.
local function setup_board_sections()
  require('org.lazy').on_load('org.agenda.render', 'super_agenda_sections', function(render)
    local grouper = render.grouper
    if not grouper then
      return
    end
    -- lines insert_header writes for `block`'s header (the same split it
    -- does: `\n`, blank lines dropped; "" and nil are the no-header cases)
    local function header_lines(block)
      local h = block.header
      if type(h) == 'function' then
        h = h()
      end
      return #vim.split(tostring(h or ''), '\n', { trimempty = true })
    end
    render.grouper = function(b, rows, block, ctx, add, day)
      local hidden = block and block.hide_empty and #rows == 0
      if hidden then
        for _ = 1, header_lines(block) do
          table.remove(b.lines)
        end
        if b.block_starts and #b.block_starts > 0 then
          table.remove(b.block_starts)
        end
        return true
      end
      if block and block.rule_above and b.block_starts and #b.block_starts > 0 then
        local pos = b.block_starts[#b.block_starts]
        -- nothing above (every open section was empty): a rule would top the view
        if pos > 1 then
          insert_rule(b, pos, ctx.width)
        end
      end
      if not (block and block.state_sections and block.super_groups) then
        return grouper(b, rows, block, ctx, add, day)
      end
      local opts = require('org.extensions').opts 'super_agenda'
      local header, final = opts.header_separator, opts.final_group_separator
      opts.header_separator = '─'
      opts.final_group_separator = '\n'
      local ok, result = pcall(grouper, b, rows, block, ctx, add, day)
      opts.header_separator = header
      opts.final_group_separator = final
      if not ok then
        error(result, 0)
      end
      return result
    end
  end)
end

-- A board view is several sections, and org.nvim joins blocks with
-- org-agenda-block-separator, a rule by default (render.view). On the board
-- a rule belongs inside a section -- it splits the per-state subsections the
-- grouper draws -- so the between-block one is turned off: each section
-- leaves the blank line from the final separator above, and that is what
-- separates them. The option is the view-wide default, read when the view is
-- rendered; a `block_separator` a block sets itself is untouched
-- (with_block_options restores it around the block anyway).
local function setup_board_view()
  require('org.lazy').on_load('org.agenda.render', 'board_block_separator', function(render)
    local view = render.view
    if not view then
      return
    end
    render.view = function(v, ctx)
      local board = false
      for _, block in ipairs(v.blocks or {}) do
        if block.state_sections then
          board = true
          break
        end
      end
      if not board then
        return view(v, ctx)
      end
      local acfg = require('org.config').opts.agenda
      local separator = acfg.block_separator
      acfg.block_separator = false
      local ok, result = pcall(view, v, ctx)
      acfg.block_separator = separator
      if not ok then
        error(result, 0)
      end
      return result
    end
  end)
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
-- The `°` TODO view of a headline project (helpers/org/project.lua) scopes
-- the agenda to that headline's subtree with a line range, fixed when the
-- view opens. A capture started from the view files its entry at the end of
-- the subtree -- past that end -- so the re-render the capture triggers
-- would drop the entry it just wrote and leave the view looking unchanged.
-- Recompute the range from the claim headline before every render. The
-- restriction carries the headline's text, so the headline is found again
-- even after edits shift its line (the anchor the plugin's own restriction
-- lock uses, org/agenda/init.lua); a restriction without it -- the lock,
-- which tracks its subtree through a buffer extmark -- is left alone.
local function setup_restrict_refresh()
  require('org.lazy').on_load('org.agenda.view', 'restrict_refresh', function(view)
    local refresh = view.refresh
    view.refresh = function(...)
      local r = view.state and view.state.restrict
      if r and r.filename and r.range and r.raw then
        local ok, file = pcall(function()
          return require('org.files').get(r.filename)
        end)
        -- the claim headline is normally still on its line; its text is the
        -- fallback for when edits above it shifted the line (a capture that
        -- bumped the entry counts changed the text, so it is tried second)
        local hl = ok and file and (file:headline_on(r.range[1]) or file:find_headline(function(h)
          return h.raw == r.raw
        end))
        if hl then
          r.range = { hl.line, hl.end_line }
        end
      end
      return refresh(...)
    end
  end)
end

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
  setup_board_sections()
  setup_board_view()
  setup_restrict_refresh()
  setup_capture_refresh()
  setup_ai()
end

return M
