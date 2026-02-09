local config = { -- Autoformat
  'stevearc/conform.nvim',
  event = 'User event_conform',
  -- //FIX: Ignore certain filetypes, slow lsp causes isses
  -- opts = {
  --   notify_on_error = false,
  --   format_on_save = {
  --     -- These options will be passed to conform.format()
  --     timeout_ms = 1500,
  --     lsp_format = 'fallback',
  --   },
  formatters_by_ft = {
    lua = { 'stylua' },
    sql = { 'sleek' },
  },
  -- },
}

return config
