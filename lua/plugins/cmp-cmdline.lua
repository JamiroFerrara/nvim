return {
  "hrsh7th/cmp-cmdline",
  enabled = true,
  event = {
    "BufReadPost",
    "BufNewFile",
    "BufWritePre"
  },
  dependencies = {
    "hrsh7th/nvim-cmp",
  },
}
