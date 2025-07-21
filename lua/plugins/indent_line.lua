return {
  { -- Add indentation guides even on blank lines
    'lukas-reineke/indent-blankline.nvim',
  enabled = not _G.NVIM_TERMINAL_ONLY,
    -- Enable `lukas-reineke/indent-blankline.nvim`
    -- See `:help ibl`
    lazy = 'BufReadPost',
    main = 'ibl',
    opts = {},
  },
}
