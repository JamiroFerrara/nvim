return {
  'JamiroFerrara/neojira.nvim',
  -- event = 'VeryLazy',
  cmd = 'Neojira',
  config = function()
    require('neojira').setup({
      browser = 'chrome.exe',
      company_name = 'novigo',
      username = 'Jamiro Ferrara'
    })
    vim.keymap.set('n', '<leader>ji', '<cmd>lua require("neojira").run()<cr>', { noremap = true, silent = true })
  end,
}
