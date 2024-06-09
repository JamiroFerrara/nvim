return {
  'folke/zen-mode.nvim',
  event = 'VeryLazy',
  mappings = {
    n = {
      ['<A-r>'] = { "<cmd>lua require('zen-mode').toggle({window= {width = 1}})<cr>" },
    },
  },
}
