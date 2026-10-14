return {
  'knownasnaffy/himalaya.nvim',
  dependencies = {
    'MunifTanjim/nui.nvim',
  },
  cmd = {
    'Himalaya',
    'HimalayaAccounts',
    'HimalayaAccount',
    'HimalayaMailboxes',
    'HimalayaFolders',
    'HimalayaMailbox',
    'HimalayaWrite',
    'HimalayaSearch',
  },
  enabled = not _G.NVIM_TERMINAL_ONLY,
  opts = {
    icons_enabled = true,
    wrap_folder_navigation = true,
  },
}
