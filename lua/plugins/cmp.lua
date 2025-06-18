return { -- Autocompletion
  'hrsh7th/nvim-cmp',
  -- event = 'InsertEnter',
  dependencies = {
    -- Snippet Engine & its associated nvim-cmp source
    {
      'L3MON4D3/LuaSnip',
      event = 'VeryLazy',
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
    },
    {'saadparwaiz1/cmp_luasnip', event = 'VeryLazy', after = 'nvim-cmp'},

    -- Adds other completion capabilities.
    --  nvim-cmp does not ship with all sources by default. They are split
    --  into multiple repos for maintenance purposes.

    {'hrsh7th/cmp-nvim-lsp', event = 'VeryLazy', after = 'nvim-cmp'},
    {'hrsh7th/cmp-path', event = 'VeryLazy', after = 'nvim-cmp'},
    {'hrsh7th/cmp-buffer', event = 'VeryLazy', after = 'nvim-cmp'},
  },

  config = function()
    -- See `:help cmp`
    local cmp = require 'cmp'
    local luasnip = require 'luasnip'
    luasnip.config.setup {
      enable_autosnippets = true,
    }

    cmp.setup {
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      completion = { completeopt = 'menu,menuone,noinsert' },
      preselect = cmp.PreselectMode.Item,
      mapping = {
        ['<Up>'] = cmp.mapping.select_prev_item(),
        ['<Down>'] = cmp.mapping.select_next_item(),
        ['<C-k>'] = cmp.mapping.select_prev_item(),
        ['<C-j>'] = cmp.mapping.select_next_item(),
        ['<A-k>'] = cmp.mapping.select_prev_item(),
        ['<A-j>'] = cmp.mapping.select_next_item(),
        ['<C-d>'] = cmp.mapping(cmp.mapping.scroll_docs(-1), { 'i', 'c' }),
        ['<C-f>'] = cmp.mapping(cmp.mapping.scroll_docs(1), { 'i', 'c' }),
        ['<C-Space>'] = cmp.mapping(cmp.mapping.complete(), { 'i', 'c' }),
        ['<A-l>'] = cmp.mapping {
          i = cmp.mapping.abort(),
          c = cmp.mapping.close(),
        },
        -- ['<C-l>'] = cmp.mapping(function()
        --   if luasnip.expand_or_locally_jumpable() then
        --     luasnip.expand_or_jump()
        --   end
        -- end, { 'i', 's' }),
        -- ['<C-h>'] = cmp.mapping(function()
        --   if luasnip.locally_jumpable(-1) then
        --     luasnip.jump(-1)
        --   end
        -- end, { 'i', 's' }),
        ['<CR>'] = cmp.mapping.confirm { select = true },
      },
      window = {
        completion = cmp.config.window.bordered(border_opts),
        documentation = cmp.config.window.bordered(border_opts),
      },

      sources = {
        { name = 'luasnip' },
        { name = 'nvim_lsp' },
        { name = 'buffer' },
        { name = 'path' },
        { name = 'vim-dadbod-completion' },
      },
    }
  end,
}
