return {
  'nvimdev/lspsaga.nvim',
  event = 'VeryLazy',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  opts = {},
  dependencies = {
    'nvim-treesitter/nvim-treesitter', -- optional
    'nvim-tree/nvim-web-devicons', -- optional
  },
}
