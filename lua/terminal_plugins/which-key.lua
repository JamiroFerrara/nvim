-- Lives in terminal_plugins/ (always imported) so the tmux `nvim +terminal`
-- session -- what `alt+o` opens -- its key hints, org.nvim's groups included,
-- instead of being off there (which-key was gated on NVIM_TERMINAL_ONLY).
return {
  'folke/which-key.nvim',
  event = 'VeryLazy',
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
