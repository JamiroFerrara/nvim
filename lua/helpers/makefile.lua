local M = {}

-- FIX: Not really working, variables seem broken.
-- Also something wrong with autocommands, it seems to be re-setting after a while
function _G.makefile_foldexpr()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum)

  -- 1. Start a new fold at level 1 for targets
  -- Matches "target:", but ignores "VAR :=" or comments
  if line:match('^[^%s#][^:]*:[^=]') then
    return '>1'
  end

  -- 2. Handle whitespace/empty lines
  -- Using "=" allows the line to "inherit" the fold level of the 
  -- target above it, effectively including the whitespace in that fold.
  if line:match('^%s*$') then
    return '='
  end

  -- 3. For recipes (indented lines) and everything else
  return '1'
end

M.fold_makefile_commands = function()
  -- Save view to restore cursor position and scroll later
  local view = vim.fn.winsaveview()

  -- Iterate through all lines
  local total_lines = vim.fn.line('$')
  for lnum = 1, total_lines do
    local line_content = vim.fn.getline(lnum)

    -- Pattern: Start of line, NOT a space/tab/hash, followed by a colon
    -- This identifies "target:" lines correctly.
    if line_content:match('^%s*[^%s]+.*:') then
      -- 'zc' specifically CLOSES the fold at this line
      -- We use pcall to prevent errors if a fold doesn't exist yet
      vim.api.nvim_win_set_cursor(0, {lnum, 0})
      pcall(vim.cmd, 'normal! zc')
    end
  end

  -- Restore original cursor position
  vim.fn.winrestview(view)
end

M.set_makefile_folding = function()
  vim.api.nvim_set_keymap('n', '<leader>or', "<cmd>lua require('helpers.makefile').fold_makefile_commands()<cr>", { noremap = true, silent = true })

  vim.opt_local.foldmethod = 'expr'
  vim.opt_local.foldexpr = 'v:lua._G.makefile_foldexpr()'
  vim.opt_local.foldlevel = 99
end

return M
