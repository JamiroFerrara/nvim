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
  end,
})

vim.api.nvim_create_autocmd("TermClose", {
  pattern = "*",
  callback = function()
    vim.cmd("qa!")  -- quit all without saving
  end,
})

vim.api.nvim_create_autocmd("FocusLost", {
    pattern = "*",
    callback = function()
        vim.cmd("hi TermCursor cterm=reverse gui=reverse")
    end,
})
vim.api.nvim_create_autocmd("FocusGained", {
    pattern = "*",
    callback = function()
        vim.cmd("hi TermCursor cterm=NONE gui=NONE")
    end,
})
