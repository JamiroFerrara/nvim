return {
  {
    'JamiroFerrara/neopostman.nvim',
    event = 'VeryLazy',
    dependencies = { 'MunifTanjim/nui.nvim' },
    config = function()
      require('neopostman').setup {}
      vim.keymap.set('t', '<leader>p', '<cmd>Neopostman<cr>', { noremap = true, silent = true })
      vim.keymap.set('t', '<leader>g', '<cmd>Neogithub<cr>', { noremap = true, silent = true })
      vim.keymap.set('t', '<leader>m', '<cmd>Neomake<cr>', { noremap = true, silent = true })
      -- vim.keymap.set('t', '<C->', '<cmd>lua require("neogithub").run()<cr>', { noremap = true, silent = true })
    end,
  },
}
