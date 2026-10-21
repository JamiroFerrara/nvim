--- Oil's entry points and the preview sidebar it opens beside itself: a narrow
--- oil column on the left, the entry under the cursor in the wide split to its
--- right, paged with `J` / `K` (helpers/preview_pane) the way the org agenda's
--- `L` preview is.
--- Shared by the plugin's own `keys` (lua/terminal_plugins/oil.lua) and the
--- terminal buffer's keymaps (lua/autocommands.lua), which each need their own
--- mapping: a terminal buffer hears only its own.
local SIDEBAR_RATIO = 0.22
local SIDEBAR_MIN = 24

local M = {}

---@return integer? the preview window, when oil has one open
function M.preview_win()
  return require('oil.util').get_preview_win()
end

---@return integer? the preview window, when it is a split rather than the float
function M.preview_split()
  local win = M.preview_win()
  if win and vim.api.nvim_win_get_config(win).relative == '' then
    return win
  end
end

--- Oil's own column: a fraction of the screen, wide enough for a file name and
--- narrow enough to leave the preview the rest of it (and the preview at least
--- forty columns).
---@return integer
function M.sidebar_width()
  local total = vim.o.columns
  return math.min(math.max(SIDEBAR_MIN, math.floor(total * SIDEBAR_RATIO)), total - 40)
end

--- Put the sidebar up on the entry under the cursor, oil shrunk to its column.
function M.sidebar_open()
  local util = require 'oil.util'
  util.run_after_load(0, function()
    require('oil').open_preview({ vertical = true, split = 'belowright' }, function(err)
      if err then
        return
      end
      local oil_win = vim.api.nvim_get_current_win()
      local win = util.get_preview_win { include_not_owned = true }
      if win and win ~= oil_win then
        pcall(vim.api.nvim_win_set_width, oil_win, M.sidebar_width())
      end
    end)
  end)
end

--- A terminal buffer's own directory, read back through the shell, and nil
--- everywhere else.
---@return string?
local function terminal_cwd()
  if vim.bo.buftype ~= 'terminal' or not vim.b.terminal_job_id then
    return nil
  end
  local tmpfile = '/tmp/nvim_term_cwd'
  vim.fn.chansend(vim.b.terminal_job_id, 'pwd > ' .. tmpfile .. ' && clear\n')
  vim.wait(80)
  local ok, lines = pcall(vim.fn.readfile, tmpfile)
  local cwd = ok and lines[1] or nil
  if cwd == '' then
    return nil
  end
  return cwd
end

--- Open Oil — at a terminal's own directory when there is one — and, when asked
--- for it (`<Tab>`), the preview sidebar on the entry under the cursor. `<C-e>`
--- asks for none, so it is the default view.
---@param with_sidebar boolean
function M.open(with_sidebar)
  local cwd = terminal_cwd()
  if cwd then
    vim.cmd('Oil ' .. vim.fn.fnameescape(cwd))
  else
    vim.cmd 'Oil'
  end
  if with_sidebar then
    M.sidebar_open()
  end
end

return M
