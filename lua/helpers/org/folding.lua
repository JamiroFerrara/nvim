-- Re-assert org folding after nvim-origami loads for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua). nvim-origami (plugins/origami.lua)
-- loads at VeryLazy and sets a global foldmethod=expr + treesitter foldexpr.
-- When an org buffer is already open at startup, that lands after org's
-- window-local fold setup and flattens the #+STARTUP visibility (the org
-- treesitter parser is not installed, so its foldexpr finds no folds).
-- Re-assert org folding for org windows once origami has loaded:
-- setup_buffer restores the fold options, set_startup_visibility reopens/
-- closes to the STARTUP mode.
--
-- show_jump_target is the other half of the file: folding a buffer entered
-- from the agenda/TODO list back to the #+STARTUP rule before unfolding the
-- entry that was entered.
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd('User', {
    pattern = 'VeryLazy',
    callback = function()
      local fold = require 'org.fold'
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'org' then
          fold.setup_buffer(buf)
          for _, win in ipairs(vim.fn.win_findbuf(buf)) do
            vim.api.nvim_win_call(win, function()
              fold.set_startup_visibility()
            end)
          end
        end
      end
    end,
  })
end

--- Fold the current window to its buffer's #+STARTUP rule, then unfold the
--- entry at the cursor with its subtree (drawers folded) -- what the agenda
--- RET/<Tab> and the TODO picker call after jumping into a file. The rule
--- from the header is applied when a buffer is loaded (org.fold.setup_buffer),
--- not when it is shown again: a file left unfolded (`zR`, or simply never
--- folded in the window it is shown in) stays unfolded like that, and the
--- `zv` of the jump does nothing when nothing is closed. Hence re-apply the
--- rule first, then show the tree that was entered -- org.fold.show_level
--- level 3, the SUBTREE level of org-agenda-show-1.
function M.show_jump_target()
  local fold = require 'org.fold'
  if vim.wo.foldexpr ~= "v:lua.require'org.fold'.foldexpr(v:lnum)" then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  fold.apply_startup(0)
  fold.show_level(lnum, 3)
end

return M
