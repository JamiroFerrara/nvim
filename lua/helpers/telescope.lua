local M = {}

function M.is_telescope_open()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local buf_ft = vim.api.nvim_buf_get_option(buf, 'filetype')
    if buf_ft == 'TelescopePrompt' then
      return true
    end
  end
  return false
end

return M
