return {
  'tpope/vim-dadbod',
  cmd = { 'DBUI', 'DBUIToggle', 'DBUIFindBuffer', 'DBUIRenameBuffer' },
  event = 'VeryLazy',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  dependencies = {
    'kristijanhusak/vim-dadbod-ui',
    'kristijanhusak/vim-dadbod-completion',
  },
}
