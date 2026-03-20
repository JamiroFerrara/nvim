-- See the kickstart.nvim README for more information
return {
  -- Improvements
  { 'lewis6991/impatient.nvim', config = function() require('impatient') end },
  { 'max397574/better-escape.nvim', event = 'InsertEnter'},
  { 'haya14busa/is.vim', event = 'InsertEnter', enabled = not _G.NVIM_TERMINAL_ONLY, },
  { 'tpope/vim-sleuth', event = 'BufReadPre', enabled = not _G.NVIM_TERMINAL_ONLY, },
  { 'folke/zen-mode.nvim', event = 'VeryLazy', enabled = true,},
  { 'junegunn/vim-easy-align', event = 'VeryLazy', enabled = not _G.NVIM_TERMINAL_ONLY, }
}
