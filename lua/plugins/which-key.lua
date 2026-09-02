return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  opts = {
    plugins = {
      presets = {
        windows = false, -- <C-w> is remapped to Harpoon navigation
      },
    },
    spec = {
      {
        '<leader>?',
        function()
          require('which-key').show { global = false }
        end,
        desc = 'Buffer Local Keymaps',
      },
      { '<leader>a', group = 'AI / Assist', mode = { 'n', 'v' } },
      { '<leader>f', group = 'Find / Format' },
      { '<leader>g', group = 'Git' },
      { '<leader>h', group = 'Helpers' },
      { '<leader>l', group = 'LSP / Lazy' },
      { '<leader>m', group = 'Make' },
      { '<leader>o', group = 'Org' },
      { '<leader>s', group = 'Search / Source' },
      { '<leader>t', group = 'Toggle / Terminal' },
    },
  },
}
