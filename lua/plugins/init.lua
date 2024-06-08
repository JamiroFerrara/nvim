-- See the kickstart.nvim README for more information
return {
  -- Colorscheme
  { 'catppuccin/nvim', event = 'VeryLazy' },

  -- Improvements
  { 'ThePrimeagen/harpoon', event = 'VeryLazy' },
  { 'lewis6991/impatient.nvim' },
  { 'ggandor/lightspeed.nvim', event = 'InsertEnter' },
  { 'max397574/better-escape.nvim', event = 'InsertEnter' },
  { 'nvim-pack/nvim-spectre', opts = {}, event = 'CmdlineEnter' },
  { 'gbprod/substitute.nvim', event = 'VeryLazy' },
  { 'haya14busa/is.vim', event = 'InsertEnter' },
  { 'tpope/vim-sleuth', event = 'BufReadPre' },
  { 'folke/zen-mode.nvim', event = 'VeryLazy' },

  -- { 'aserowy/tmux.nvim', opts = {}, event = 'VeryLazy' },
  -- { 'nacro90/numb.nvim', opts = {}, event = 'VeryLazy' },
}