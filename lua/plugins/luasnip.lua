return {
  'L3MON4D3/LuaSnip',
  -- event = 'VeryLazy',
  event = {
    "BufReadPost",
    "BufNewFile",
    "BufWritePre"
  },
  build = (function()
    -- Build Step is needed for regex support in snippets.
    -- This step is not supported in many windows environments.
    -- Remove the below condition to re-enable on windows.

    if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
      return
    end
    return 'make install_jsregexp'
  end)(),
  dependencies = {
    -- {
    --   'rafamadriz/friendly-snippets',
    --   config = function()
    --     require('luasnip.loaders.from_vscode').lazy_load()
    --   end,
    -- },
  },
  config = function()
    local user_settings = {

      filetype_extend = {
        javascript = { 'javascriptreact' },
      },
      -- Configure luasnip loaders (vscode, lua, and/or snipmate)
      lua = {
        paths = { '~/dotfiles/nvim/snippets/lua-snippets/' },
      },
      snipmate = {
        paths = { '~/dotfiles/nvim/snippets/snipmate-snippets/' },
      },
    }
    local loader = require 'luasnip.loaders.from_snipmate'
    loader.lazy_load()
    local paths = user_settings.snipmate.paths
    if paths then
      loader.lazy_load { paths = paths }
    end
  end,
}
