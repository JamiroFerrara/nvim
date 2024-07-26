-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- TODO: Close folds on markdown
-- vim.api.nvim_create_autocmd('BufRead', {
--   pattern = '*.md',
--   nested = true,
--   callback = function()
--     vim.api.nvim_command 'normal! za'
--   end,
-- })
