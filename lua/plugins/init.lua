-- See the kickstart.nvim README for more information
return {
  -- Colorscheme
  { 'catppuccin/nvim', event = 'VeryLazy' },

  -- Improvements
  { 'lewis6991/impatient.nvim' },
  { 'ThePrimeagen/harpoon', event = 'VeryLazy', enabled = not _G.NVIM_TERMINAL_ONLY, },
  { 'ggandor/lightspeed.nvim', event = 'InsertEnter' },
  { 'max397574/better-escape.nvim', event = 'InsertEnter'},
  { 'nvim-pack/nvim-spectre', opts = {}, event = 'CmdlineEnter', enabled = not _G.NVIM_TERMINAL_ONLY, },
  { 'gbprod/substitute.nvim', event = 'VeryLazy', enabled = not _G.NVIM_TERMINAL_ONLY, },
  { 'haya14busa/is.vim', event = 'InsertEnter', enabled = not _G.NVIM_TERMINAL_ONLY, },
  { 'tpope/vim-sleuth', event = 'BufReadPre', enabled = not _G.NVIM_TERMINAL_ONLY, },
  { 'folke/zen-mode.nvim', event = 'VeryLazy'},
}
