return {
  "hrsh7th/cmp-nvim-lua",
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
