-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-- On buffer enter require("harpoon.ui").nav_file(1);
vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'On buffer enter set highlights',
  group = vim.api.nvim_create_augroup('kickstart-harpoon-nav', { clear = true }),
  callback = function()
    vim.cmd 'highlight LineNr guifg=#b4befe'
  end,
})
