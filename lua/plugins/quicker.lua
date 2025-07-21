return {
  'stevearc/quicker.nvim',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  event = "FileType qf",
  ---@module "quicker"
  ---@type quicker.SetupOptions
  opts = {},
}
