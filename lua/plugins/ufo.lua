-- FIX: Not working
return {
  'kevinhwang91/nvim-ufo',
  dependencies = {
    'kevinhwang91/promise-async',
  },
  lazy = true,
  config = function()

    vim.keymap.set('n', 'zR', require('ufo').openAllFolds)
    vim.keymap.set('n', 'zM', require('ufo').closeAllFolds)

    require('ufo').setup {
      provider_selector = function(bufnr, filetype, buftype)
        return { 'treesitter', 'indent' }
      end,
    }
  end,
}
