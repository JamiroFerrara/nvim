-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
  })

vim.api.nvim_create_autocmd("BufWinEnter", {
  pattern = { "*.md" },
  callback = function()
    vim.opt.colorcolumn = "80"
    vim.opt.textwidth = 80
  end,
})

vim.api.nvim_create_autocmd("TermOpen", {
  pattern = "*",
  callback = function()
    vim.cmd("startinsert")
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.laststatus = 0
    vim.wo.signcolumn = "no"
    vim.opt_local.modifiable = true
    vim.opt_local.readonly = false
    vim.api.nvim_buf_set_keymap(0, "n", "<Tab>", "<cmd>Oil<CR>", { noremap = true, silent = true, desc = "Enter Oil if in terminal normal mode" })
  end,
})

vim.api.nvim_create_autocmd("TermClose", {
  pattern = "*",
  callback = function()
    vim.cmd("qa!")  -- quit all without saving
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  pattern = "*.http",
  callback = function()
    vim.api.nvim_set_keymap('n', '<cr>', "<cmd>lua require('kulala').run()<cr>", { noremap = true, silent = true })
    vim.api.nvim_set_keymap('n', 'p', "<cmd>lua require('kulala').from_curl()<cr>", { noremap = true, silent = true })
  end,
})

vim.api.nvim_create_autocmd("FocusLost", {
    pattern = "*",
    callback = function()
        vim.cmd("hi TermCursor cterm=NONE gui=NONE")
    end,
})
vim.api.nvim_create_autocmd("FocusGained", {
    pattern = "*",
    callback = function()
        vim.cmd("hi TermCursor cterm=reverse gui=reverse")
    end,
})
