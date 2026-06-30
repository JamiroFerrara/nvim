-- Git file history (telescope extension). Merged with main telescope spec via lazy.nvim.
return {
  'nvim-telescope/telescope.nvim',
  -- No event/keys here — main telescope spec in terminal_plugins already handles laziness.
  dependencies = {
    {
      'isak102/telescope-git-file-history.nvim',
      dependencies = {
        'nvim-lua/plenary.nvim',
        'tpope/vim-fugitive',
      },
    },
  },
}
