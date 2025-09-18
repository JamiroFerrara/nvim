local M = {}

function M.yank_code_block()
  local cursor = vim.api.nvim_win_get_cursor(0) -- {row, col}
  local row = cursor[1]
  local buf = 0
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local start_line, end_line = nil, nil

  -- First, look upward for a closing fence ```
  for i = row, 1, -1 do
    if lines[i] and lines[i]:match("^```") then
      end_line = i - 1
      -- look further up for opening fence ```
      for j = i - 1, 1, -1 do
        if lines[j] and lines[j]:match("^```") then
          start_line = j + 1
          break
        end
      end
      break
    end
  end

  -- If not found, maybe we're inside a block → find opening first
  if not start_line then
    for i = row, 1, -1 do
      if lines[i] and lines[i]:match("^```") then
        start_line = i + 1
        -- now search forward for closing ```
        for j = i + 1, #lines do
          if lines[j] and lines[j]:match("^```") then
            end_line = j - 1
            break
          end
        end
        break
      end
    end
  end

  if start_line and end_line and start_line <= end_line then
    local block = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
    vim.fn.setreg("+", table.concat(block, "\n"))
    vim.notify("Yanked code block to clipboard")
  else
    vim.notify("No code block found")
  end
end

return M
