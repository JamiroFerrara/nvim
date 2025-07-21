return {
  'folke/trouble.nvim',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  opts = {
    auto_close = true,
  }, -- for default options, refer to the configuration section for custom setup.
  cmd = 'Trouble',
  event = 'VeryLazy',
  keys = {
    {
      '<leader>lx',
      '<cmd>Trouble diagnostics filter.severity=vim.diagnostic.severity.ERROR <cr>',
      desc = 'Diagnostics (Trouble)',
    },
    {
      '<leader>lX',
      '<cmd>Trouble diagnostics filter.severity=vim.diagnostic.severity.WARNING <cr>',
      desc = 'Buffer Diagnostics (Trouble)',
    },
    -- {
    --   '<leader>cs',
    --   '<cmd>Trouble symbols toggle focus=false<cr>',
    --   desc = 'Symbols (Trouble)',
    -- },
    -- {
    --   '<leader>cl',
    --   '<cmd>Trouble lsp toggle focus=false win.position=right<cr>',
    --   desc = 'LSP Definitions / references / ... (Trouble)',
    -- },
    {
      '<leader>xL',
      '<cmd>Trouble loclist toggle<cr>',
      desc = 'Location List (Trouble)',
    },
    {
      '<leader>xQ',
      '<cmd>Trouble qflist toggle<cr>',
      desc = 'Quickfix List (Trouble)',
    },
  },
}
