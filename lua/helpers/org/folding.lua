-- Re-assert org folding after nvim-origami loads for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua). nvim-origami (plugins/origami.lua)
-- loads at VeryLazy and sets a global foldmethod=expr + treesitter foldexpr.
-- When an org buffer is already open at startup, that lands after org's
-- window-local fold setup and flattens the #+STARTUP visibility (the org
-- treesitter parser is not installed, so its foldexpr finds no folds).
-- Re-assert org folding for org windows once origami has loaded:
-- setup_buffer restores the fold options, set_startup_visibility reopens/
-- closes to the STARTUP mode.
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

return M
