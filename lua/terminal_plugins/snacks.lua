return {
  'folke/snacks.nvim',
  -- enabled = not _G.NVIM_TERMINAL_ONLY,
  event = 'VeryLazy',
  ---@type snacks.Config
  -- priority = 1000, -- removed to avoid startup loading
  opts = {
    -- your configuration comes here
    -- or leave it empty to use the default settings
    -- refer to the configuration section below
    explorer = { enabled = false },
    quickfile = { enabled = true },
    bigfile = { enabled = true },
    indent = { enabled = true },
    input = { enabled = true },
    notifier = { enabled = true },
  },
}
