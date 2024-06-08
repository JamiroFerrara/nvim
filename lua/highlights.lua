vim.api.nvim_create_autocmd('BufEnter', {
  pattern = '*.cs',
  nested = true,
  callback = function()
    vim.cmd 'hi @type.builtin guifg=#89b4fa'
    vim.cmd 'hi @parameter guifg=#cdd6f4'
    vim.cmd 'hi @field guifg=#cdd6f4'
    vim.cmd 'hi @function guifg=#b4befe'
    vim.cmd 'hi @method guifg=#b4befe'
    vim.cmd 'hi @keyword guifg=#cba6f7'
    vim.cmd 'hi @method.call guifg=#89b4fa'
  end,
})
