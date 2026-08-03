local M = {}

local TERM_PREFIX = 'term:make:'

function M.run_or_focus(name, command)
  local term_name = TERM_PREFIX .. name

  -- Search for existing buffer with the same name
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.fn.bufname(buf) == term_name then
      local win = vim.fn.bufwinnr(buf)
      if win ~= -1 then
        vim.api.nvim_set_current_win(win)
      else
        vim.api.nvim_set_current_buf(buf)
      end
      vim.fn.chansend(vim.b.terminal_job_id, command .. '\n')
      vim.cmd.startinsert()
      return
    end
  end

  -- No existing buffer found, create a new terminal with the command
  vim.cmd('terminal $SHELL -c "' .. command .. '; $SHELL"')
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, term_name)
  vim.bo[buf].bufhidden = 'hide'
end
return M
