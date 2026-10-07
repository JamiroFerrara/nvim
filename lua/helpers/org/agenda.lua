-- Agenda-side customizations for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): the `D` toggle_done action, and
-- opening the agenda without throwing away the window layout. Both plug
-- into modules the plugin loads on first use, so they go through
-- org.lazy.on_load and nothing here is required at startup.
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

-- org.nvim's "split" agenda window is Emacs' reorganize-frame: show_buffer
-- (view/window.lua) runs `silent! only`, so the agenda becomes the only
-- other window and an open vsplit is thrown away. Instead the agenda should
-- land in a full-width split *below* the existing windows -- `botright
-- split`, which `fit_window` then sizes. Drop just that `silent! only` for
-- the opening call; `agenda.window = "only"` and the quit-time layout
-- restore keep their own.
local function without_only(fn, ...)
  local cmd = vim.cmd
  vim.cmd = function(c, ...)
    if type(c) == 'string' and c == 'silent! only' then
      return
    end
    return cmd(c, ...)
  end
  local ok, err = pcall(fn, ...)
  vim.cmd = cmd
  if not ok then
    error(err)
  end
end

--- Whether the agenda window mode keeps the other windows.
local function keeps_windows()
  local mode = require('org.config').opts.agenda.window
  return mode == nil or mode == 'split' or mode == 'reorganize-frame'
end

-- Launching the agenda from a terminal window (the `nvim +terminal` session)
-- should take that window over, not split below the terminal. org.agenda.open
-- reads agenda.window in show_buffer() while it runs, so swap in "current"
-- for the call when the buffer is a terminal. The wrapper is installed when
-- org.agenda first loads (the agenda command requiring it), which is before
-- any of its functions run.
local function setup_open()
  require('org.lazy').on_load('org.agenda', 'window_setup', function(agenda)
    local agenda_open = agenda.open
    agenda.open = function(spec, opts)
      if vim.bo.buftype == 'terminal' then
        local config = require 'org.config'
        local saved = config.opts.agenda.window
        config.opts.agenda.window = 'current'
        local ok, err = pcall(agenda_open, spec, opts)
        config.opts.agenda.window = saved
        if not ok then
          error(err)
        end
        -- The window held a terminal buffer; its autocommands
        -- (autocommands.lua: TermOpen / FocusGained / BufEnter term://*)
        -- call startinsert, and that lands in the agenda buffer right
        -- after it is set (logged: FileType orgagenda, then
        -- InsertEnter buftype=nofile name=agenda). Exit insert/terminal
        -- mode now, and once more for the insert that follows.
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
        return
      end
      if keeps_windows() then
        return without_only(agenda_open, spec, opts)
      end
      return agenda_open(spec, opts)
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

function M.setup()
  setup_toggle_done()
  setup_open()
  setup_pick_todo()
end

return M
