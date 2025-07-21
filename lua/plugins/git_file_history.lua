return {
    "nvim-telescope/telescope.nvim",
    event = "VeryLazy",
    -- enabled = not _G.NVIM_TERMINAL_ONLY,
    dependencies = {
        {
            "isak102/telescope-git-file-history.nvim",
            dependencies = {
                "nvim-lua/plenary.nvim",
                "tpope/vim-fugitive"
            }
        }
    }
}
