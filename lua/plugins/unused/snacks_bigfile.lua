return {
  'folke/snacks.nvim',
  -- enabled = not _G.NVIM_TERMINAL_ONLY,
  priority = 1000,
  lazy = false,
  ---@type snacks.Config
  opts = {
    bigfile = { enabled = true },
  },
}
