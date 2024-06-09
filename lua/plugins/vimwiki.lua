return {
  'vimwiki/vimwiki',
  event = 'VeryLazy',
  mappings = {
    n = {
      ['<leader><cr>'] = { '<cmd>VimwikiToggleListItem<cr>', desc = 'Toggle Vimwiki list item' },
    },
  },
}
