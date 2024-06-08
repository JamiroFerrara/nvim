return {
  'L3MON4D3/LuaSnip',
  event = 'InsertEnter',
  opts = {},
  config = function()
    local luasnip = require 'luasnip'
    local types = require 'luasnip.util.types'
    -- if user_settings.config then luasnip.config.setup(user_settings.config) end
    luasnip.config.set_config {
      history = true,
      enable_autosnippets = true,
      updateevents = 'TextChanged,TextChangedI',
      ext_opts = {
        [types.choiceNode] = {
          active = {
            virt_text = { { '<--', 'Error' } },
          },
        },
      },
    }
  end,
}
