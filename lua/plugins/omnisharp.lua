return {
  'Hoffs/omnisharp-extended-lsp.nvim',
  -- event = 'VeryLazy',
  event = "BufReadPost *.cs",
  enabled = not _G.NVIM_TERMINAL_ONLY,
}
