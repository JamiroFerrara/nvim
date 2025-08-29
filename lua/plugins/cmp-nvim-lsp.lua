return {
  "hrsh7th/cmp-nvim-lsp",
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
