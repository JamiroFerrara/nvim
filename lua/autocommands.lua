-------------------------------------------------
-- [MISCELLANEUS]
-------------------------------------------------

-- Highlight when yanking (copying) text
vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

-------------------------------------------------
-- [C#]
-------------------------------------------------

vim.api.nvim_create_autocmd('BufWinEnter', {
  pattern = '*.cs',
  callback = function()
    vim.api.nvim_set_keymap('n', 'gd', "<cmd>lua require('omnisharp_extended').lsp_definition()<cr>", {})
  end,
})

-------------------------------------------------
-- [TERMINAL]
-------------------------------------------------

vim.api.nvim_create_autocmd('FocusLost', {
  pattern = '*',
  callback = function()
    vim.cmd 'hi TermCursor cterm=reverse gui=reverse'
  end,
})

vim.api.nvim_create_autocmd('FocusGained', {
  pattern = '*',
  callback = function()
    vim.cmd 'hi TermCursor cterm=NONE gui=NONE'
  end,
})

vim.api.nvim_create_autocmd('TermOpen', {
  pattern = '*',
  callback = function()
    vim.cmd 'startinsert'
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.laststatus = 0
    vim.wo.signcolumn = 'no'
    vim.opt_local.modifiable = true
    vim.opt_local.readonly = false
    vim.api.nvim_buf_set_keymap(0, 'n', '<Tab>', '<cmd>Oil<CR>',
      { noremap = true, silent = true, desc = 'Enter Oil if in terminal normal mode' })
  end,
})

vim.api.nvim_create_autocmd("FocusGained", {
  pattern = "term://*",
  command = "startinsert"
})

vim.api.nvim_create_autocmd('TermClose', {
  pattern = '*',
  callback = function()
    vim.cmd 'q!' -- quit all without saving
  end,
})

-------------------------------------------------
-- [MARKDOWN]
-------------------------------------------------

vim.api.nvim_create_autocmd('BufWritePre', {
  pattern = '*.md',
  callback = function()
    vim.cmd([[
      silent! TableModeEnable
      silent! TableModeRealign
      silent! TableEvalFormulaLine
      silent! TableModeDisable
    ]])
  end,
})

-- Use autocommand to apply only to markdown files
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = require('helpers.markdown').set_markdown_folding,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "org",
  callback = require('helpers.org').set_org_folding,
})

-- FIX: This runs each time a buffer viewed, should do just once
-- vim.api.nvim_create_autocmd({ 'BufWinEnter' }, {
--   pattern = { '*.md' },
--   callback = function()
--     -- Auto folds on buf enter
--     require('helpers.markdown').fold_headings_of_level(3)
--   end,
-- })

-- FIX: Breaks highlights
-- vim.api.nvim_create_autocmd('BufWinEnter', {
--   pattern = { '*.md' },
--   callback = function()
--     vim.opt.textwidth = 80
--
--     -- Generic Markdown fold text
--     function _G.MarkdownFoldText()
--       local line = vim.fn.getline(vim.v.foldstart)
--       return line:gsub("^%s*", "")
--     end
--
--     -- Simplified TODO.md fold text (only done vs not done)
--     function _G.TodoFoldText()
--       local start_line = vim.v.foldstart
--       local end_line = vim.v.foldend
--       local header = vim.fn.getline(start_line):gsub("^%s*", "")
--
--       local done = 0
--       local total = 0
--
--       for i = start_line + 1, end_line do
--         local l = vim.fn.getline(i):gsub("^%s*", "")
--         local checkbox = l:match("^%- %[(.)%]")
--         if checkbox then
--           total = total + 1
--           if checkbox == "x" or checkbox == "X" then
--             done = done + 1
--           end
--         end
--       end
--
--       local percent_done = total > 0 and math.floor((done / total) * 100) or 0
--
--       if total > 0 then
--         return string.format("%s [%d/%d - %d%%]", header, done, total, percent_done)
--       else
--         return header
--       end
--     end
--
--     -- Apply foldtext depending on filename
--     local file = vim.fn.expand("%:t")
--     if file == "TODO.md" then
--       vim.o.foldtext = 'v:lua.TodoFoldText()'
--     else
--       vim.o.foldtext = 'v:lua.MarkdownFoldText()'
--     end
--   end,
-- })
