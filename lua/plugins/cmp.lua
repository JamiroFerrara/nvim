return { -- Autocompletion
  'hrsh7th/nvim-cmp',
  -- event = 'InsertEnter',
  dependencies = {
    -- Snippet Engine & its associated nvim-cmp source
    {
      'onsails/lspkind.nvim',
      'L3MON4D3/LuaSnip',
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
          -- Extend filetypes
          filetype_extend = {
            javascript = { 'javascriptreact' },
          },
          -- Configure luasnip loaders (vscode, lua, and/or snipmate)
          lua = {
            paths = { '~/home/jferrara/.config/nvim/lua/user/snippets/lua-snippets/' },
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
    'saadparwaiz1/cmp_luasnip',

    -- Adds other completion capabilities.
    --  nvim-cmp does not ship with all sources by default. They are split
    --  into multiple repos for maintenance purposes.

    'hrsh7th/cmp-nvim-lsp',
    'hrsh7th/cmp-path',
    'hrsh7th/cmp-buffer',
  },

  config = function()
    -- See `:help cmp`
    local cmp = require 'cmp'
    local luasnip = require 'luasnip'
    luasnip.config.setup {
      enable_autosnippets = true,
    }

    local lspkind = require 'lspkind'
    cmp.setup {
      formatting = {
        format = lspkind.cmp_format {
          mode = 'symbol_text', -- show only symbol annotations
          maxwidth = {
            -- prevent the popup from showing more than provided characters (e.g 50 will not show more than 50 characters)
            -- can also be a function to dynamically calculate max width such as
            -- menu = function() return math.floor(0.45 * vim.o.columns) end,
            menu = 50, -- leading text (labelDetails)
            abbr = 50, -- actual suggestion item
          },
          ellipsis_char = '...', -- when popup menu exceed maxwidth, the truncated part would show ellipsis_char instead (must define maxwidth first)
          show_labelDetails = true, -- show labelDetails in menu. Disabled by default

          -- The function below will be called before any actual modifications from lspkind
          -- so that you can provide more controls on popup customization. (See [#30](https://github.com/onsails/lspkind-nvim/pull/30))
          before = function(entry, vim_item)
            return vim_item
          end,
        },
      },
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
        ['<C-d>'] = cmp.mapping(cmp.mapping.scroll_docs(-1), { 'i', 'c' }),
        ['<C-f>'] = cmp.mapping(cmp.mapping.scroll_docs(1), { 'i', 'c' }),
        ['<C-Space>'] = cmp.mapping(cmp.mapping.complete(), { 'i', 'c' }),
        ['<C-l>'] = cmp.mapping {
          i = cmp.mapping.abort(),
          c = cmp.mapping.close(),
        },
        ['<CR>'] = cmp.mapping.confirm { select = true },
      },
      window = {
        completion = cmp.config.window.bordered(border_opts),
        documentation = cmp.config.window.bordered(border_opts),
      },

      -- mapping = cmp.mapping.preset.insert {
      --   ['<C-n>'] = cmp.mapping.select_next_item(),
      --   ['<C-p>'] = cmp.mapping.select_prev_item(),
      --   ['<C-b>'] = cmp.mapping.scroll_docs(-4),
      --   ['<C-f>'] = cmp.mapping.scroll_docs(4),
      --   ['<C-y>'] = cmp.mapping.confirm { select = true },
      --   ['<C-Space>'] = cmp.mapping.complete {},
      --   ['<C-l>'] = cmp.mapping(function()
      --     if luasnip.expand_or_locally_jumpable() then
      --       luasnip.expand_or_jump()
      --     end
      --   end, { 'i', 's' }),
      --   ['<C-h>'] = cmp.mapping(function()
      --     if luasnip.locally_jumpable(-1) then
      --       luasnip.jump(-1)
      --     end
      --   end, { 'i', 's' }),
      -- },

      sources = {
        { name = 'luasnip' },
        { name = 'buffer' },
        { name = 'nvim_lsp' },
        { name = 'path' },
        { name = 'vim-dadbod-completion' },
      },
    }
  end,
}
