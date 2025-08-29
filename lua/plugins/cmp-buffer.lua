return {
  "hrsh7th/cmp-buffer",
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
