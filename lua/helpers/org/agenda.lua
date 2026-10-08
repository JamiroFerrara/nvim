-- Agenda-side customizations for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): the `D` toggle_done action, the fold
-- state left behind by entering an entry, the insert mode a terminal
-- window would otherwise leave in the agenda, and the 1/2/3 switch between
-- the custom views of agenda.custom_commands. All of them plug into modules
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

-- Launching the agenda from a terminal window must not leave insert mode
-- running in the agenda buffer: the terminal's autocommands
-- (autocommands.lua: TermOpen / FocusGained / BufEnter term://*) call
-- startinsert, and that lands in the agenda buffer right after it is set
-- (logged: FileType orgagenda, then InsertEnter buftype=nofile
-- name=agenda). Exit insert/terminal mode now, and once more for the insert
-- that follows. The wrapper is installed when org.agenda first loads (the
-- agenda command requiring it), which is before any of its functions run.
local function setup_open()
  require('org.lazy').on_load('org.agenda', 'window_setup', function(agenda)
    local agenda_open = agenda.open
    agenda.open = function(spec, opts)
      if vim.bo.buftype ~= 'terminal' then
        return agenda_open(spec, opts)
      end
      local ok, err = pcall(agenda_open, spec, opts)
      if not ok then
        error(err)
      end
      local function normal_mode()
        local mode = vim.api.nvim_get_mode().mode
        if mode == 't' then
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true), 'n', false)
        elseif mode:sub(1, 1) == 'i' then
          pcall(vim.cmd, 'stopinsert')
        end
      end
      normal_mode()
      local guard = vim.api.nvim_create_autocmd('InsertEnter', {
        callback = function()
          -- stopinsert during InsertEnter does not take; leave after
          vim.defer_fn(normal_mode, 0)
        end,
      })
      vim.defer_fn(function()
        pcall(vim.api.nvim_del_autocmd, guard)
      end, 2000)
    end
  end)
end

-- <C-p> in the agenda opens the project/TODO picker: the same
-- helpers/org_todo.pick `pick_project_todo` action the global <leader>os
-- key runs (org buffers bind it through mappings.org in the plugin spec).
-- Buffer-local, so in the agenda it shadows the global fff <C-p> file
-- finder. The TODO block is rendered in the same orgagenda buffer, so one
-- mapping covers the agenda and the todo view.
local function setup_pick_todo()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'orgagenda',
    callback = function(args)
      vim.keymap.set('n', '<C-p>', function()
        require('org.actions').run 'pick_project_todo'
      end, { buffer = args.buf, desc = 'org: Pick a project, then a TODO in it' })
    end,
  })
end

-- Number keys open the custom views configured in
-- lua/terminal_plugins/org.nvim.lua (agenda.custom_commands): 1 all open
-- TODOs across every project, 2 bugs, 3 priorities. Buffer-local to
-- orgagenda -- the TODO view renders into the same buffer, so it switches
-- from there too -- which is why the keys are the plain digits and not the
-- `<leader>o` ones: a count typed in the agenda (`<C-u>` style) no longer
-- starts with 1 or 2, and nothing else claims them. `agenda.window =
-- 'current'` makes the open take the window over, so the same buffer is
-- refilled and this reads as switching view rather than stacking a second
-- agenda.
--
-- The 2 / 3 views are scoped to the project of the working directory, the
-- way `°` is for the TODO view (helpers/org/project.lua): each block's
-- `files` becomes the project's file and a headline claim adds its subtree
-- restriction. A cwd that names no project -- or one whose file does not
-- exist yet -- opens the full view, the same one the dispatcher menu's `b`
-- / `p` give. Resolution runs per key press (project.current reads getcwd,
-- or the job cwd of a terminal buffer), so a `cd` moves the scope with it.
-- 1 is global: it never scopes, so it lists the open TODOs of every project.
local CUSTOM_VIEWS = {
  { '1', 'o', 'all open TODOs', true },
  { '2', 'b', 'bugs and warnings' },
  { '3', 'p', 'open A/B priorities' },
}

local function open_custom_view(key, label, global)
  local command = (require('org.config').opts.agenda.custom_commands or {})[key]
  if not command then
    require('org.utils').warn('agenda: no custom command ' .. key)
    return
  end
  local spec, opts = vim.deepcopy(command), nil
  local project = require 'helpers.org.project'
  local current = not global and project.current() or nil
  if current and vim.uv.fs_stat(current.file) then
    local title = project.title(current)
    local files = project.files(current)
    for _, block in ipairs(spec.types or { spec }) do
      block.files = files
      -- the block header is drawn (view.title is not), so the project name
      -- goes there: an empty view -- a project with no bug, say -- still
      -- says what it filtered on instead of looking broken
      block.header = block.header and (title .. ' - ' .. block.header) or title
    end
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

function M.setup()
  setup_toggle_done()
  setup_entry_folds()
  setup_open()
  setup_pick_todo()
  setup_custom_views()
end

return M
