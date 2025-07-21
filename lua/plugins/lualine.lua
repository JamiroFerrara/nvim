return {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    enabled = not _G.NVIM_TERMINAL_ONLY,
}
