--- Open (or re-use) an `omp` terminal in a vertical split on the right.
---
---   * If a window already sits to the right of the current one it is
---     swallowed: focused in place (and dropped into insert mode when it is a
---     terminal) instead of spawning a second split.
---   * Otherwise a vertical split is created (`splitright` places it on the
---     right) and `omp` is started inside it.

local M = {}

local TERM_NAME = 'term:omp:'

---@return integer? window to the right of the current one, if any
local function right_win()
  local cur = vim.api.nvim_get_current_win()
  local cur_pos = vim.api.nvim_win_get_position(cur)
  local cur_row, cur_col = cur_pos[1], cur_pos[2]
  local cur_h = vim.api.nvim_win_get_height(cur)
  local right_edge = cur_col + vim.api.nvim_win_get_width(cur)

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= cur and vim.api.nvim_win_get_config(win).relative == '' then
      local pos = vim.api.nvim_win_get_position(win)
      local row, col = pos[1], pos[2]
      local h = vim.api.nvim_win_get_height(win)
      -- starts at (or past) the current window's right edge and shares rows
      if col >= right_edge and row < cur_row + cur_h and cur_row < row + h then
        return win
      end
    end
  end
end

function M.open()
  local win = right_win()
  if win then
    vim.api.nvim_set_current_win(win)
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == 'terminal' then
      vim.cmd 'startinsert'
    end
    return
  end

  -- `belowright` forces the new window to the right regardless of `splitright`
  vim.cmd 'belowright vsplit'
  vim.cmd 'terminal omp'
  local buf = vim.api.nvim_get_current_buf()
  pcall(vim.api.nvim_buf_set_name, buf, TERM_NAME .. buf)
  vim.bo[buf].bufhidden = 'hide'
end

return M
