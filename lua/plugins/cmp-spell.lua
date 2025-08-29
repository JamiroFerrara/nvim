return {
  "f3fora/cmp-spell",
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
