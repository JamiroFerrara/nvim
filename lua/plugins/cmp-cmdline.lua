return {
  "hrsh7th/cmp-cmdline",
  enabled = true,
  event = {
    "BufReadPost",
    "BufNewFile",
    "BufWritePre",
  },
  dependencies = {
    "hrsh7th/nvim-cmp",
  },
  -- The `cmdline` source auto-registers via the plugin's after/plugin file.
  -- The `:` cmdline completion is configured in cmp.lua (single source of
  -- truth, includes the buffer_preview source).
}

