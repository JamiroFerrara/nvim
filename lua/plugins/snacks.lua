return {
  'folke/snacks.nvim',
  -- enabled = not _G.NVIM_TERMINAL_ONLY,
  priority = 1000,
  event = 'VeryLazy', 
  ---@type snacks.Config
  opts = {
    -- your configuration comes here
    -- or leave it empty to use the default settings
    -- refer to the configuration section below
    quickfile = { enabled = true },
    bigfile = { enabled = true },
    dashboard = { enabled = true },
    indent = { enabled = true },
    input = { enabled = true },
    notifier = { enabled = true },
  },
}
