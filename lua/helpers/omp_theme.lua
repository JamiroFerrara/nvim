--- The theme the `omp` instances this config starts paint with: nvim's own, so
--- the agent's pane and the buffer beside it read as one surface.
---
--- The overlay rides on the process (`--config`), never in omp's own settings
--- directory: an `omp` started by hand keeps the theme the user picked there,
--- while every instance this config opens follows the editor. The names are
--- omp's built-in catppuccin themes (mocha on a dark terminal, latte on a light
--- one), and their syntax tokens are the colors catppuccin-nvim gives neovim
--- -- keyword mauve, function blue, string green, number peach, type yellow,
--- operator sky, comment overlay0 -- so a fenced block in the agent's reply is
--- highlighted the way the same block is highlighted in the ticket that asked
--- for it. They mirror `vim.cmd.colorscheme 'catppuccin-mocha'`
--- (lua/terminal_plugins/theme_catpuccin.lua).

local M = {}

local DARK = 'dark-catppuccin'
local LIGHT = 'light-catppuccin'

--- Where the overlay is written: nvim's cache, since it describes the editor's
--- instances rather than omp's own settings.
---@return string
local function path()
  return vim.fs.joinpath(vim.fn.stdpath 'cache', 'omp-theme.yml')
end

--- The `--config` pair for an `omp` argv, the overlay written first. Safe to
--- call per launch: the file is rewritten every time, so an edit to the theme
--- names above cannot be shadowed by a stale copy.
---@return string[]
function M.argv()
  local file = path()
  pcall(vim.fn.mkdir, vim.fs.dirname(file), 'p')
  pcall(vim.fn.writefile, {
    'theme:',
    '  dark: ' .. DARK,
    '  light: ' .. LIGHT,
  }, file)
  return { '--config', file }
end

return M
