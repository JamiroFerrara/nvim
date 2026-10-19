return { -- You can easily change to a different colorscheme.
  -- Change the name of the colorscheme plugin below, and then
  -- change the command in the config to whatever the name of that colorscheme is.
  --
  -- If you want to see what colorschemes are already installed, you can use `:Telescope colorscheme`.
  'catppuccin/nvim',
  event = 'VeryLazy',
  priority = 1000, -- Make sure to load this before all the other start plugins.
  init = function()
    -- Load the colorscheme here.
    -- Like many other themes, this one has different styles, and you could load
    -- any other, such as 'tokyonight-storm', 'tokyonight-moon', or 'tokyonight-day'.
    --
    -- setup() runs here, before the first :colorscheme, so the
    -- custom_highlights below are already in the compiled theme; doing it
    -- through lazy's `opts` would run after and only rewrite the cache.
    require('catppuccin').setup {
      custom_highlights = function(colors)
        return {
          -- snacks' dashboard startup section ("⚡ Neovim loaded 6/92
          -- plugins in 74ms"): catppuccin's snacks integration paints the
          -- footer chunk yellow-italic and the numbers pink. Both blue,
          -- like SnacksDashboardHeader.
          SnacksDashboardFooter = { fg = colors.blue, style = {} },
          -- SnacksDashboardSpecial = { fg = colors.blue },
          -- omp agent note blocks (helpers/org/decorations.lua): the icon,
          -- timestamp and rule of a 🤖-headed block, so the agent's turns
          -- read apart from the plain notes' gray Comment.
          OrgAgentTimestamp = { fg = colors.mauve },
          OrgAgentRule = { fg = colors.mauve },
          -- org.nvim's agenda group headers (the super_agenda sections:
          -- "Work", "Important", a project's title): a lavender label on a
          -- surface0 badge, so a section reads apart from the view's own
          -- blue-bold block header above it and the entries below. The
          -- trailing space that closes the badge is added by
          -- helpers/org/agenda.lua.
          OrgSuperAgendaHeader = { fg = colors.lavender, bg = colors.surface0, style = { 'bold' } },
        }
      end,
    }
    vim.cmd.colorscheme 'catppuccin-mocha'

    -- You can configure highlights by doing something like:
    vim.cmd.hi 'Comment gui=none'

    -- Custom telescope theme
    -- local colors = require('catppuccin.palettes').get_palette()
    -- local TelescopeColor = {
    --   TelescopeMatching = { fg = colors.flamingo },
    --   TelescopeSelection = { fg = colors.text, bg = colors.surface0, bold = true },
    --
    --   TelescopePromptPrefix = { bg = colors.surface0 },
    --   TelescopePromptNormal = { bg = colors.surface0 },
    --   -- TelescopeResultsNormal = { bg = colors.mantle },
    --   -- TelescopePreviewNormal = { bg = colors.mantle },
    --   TelescopePromptBorder = { bg = colors.surface0, fg = colors.surface0 },
    --   TelescopeResultsBorder = { bg = colors.mantle, fg = colors.mantle },
    --   TelescopePreviewBorder = { bg = colors.mantle, fg = colors.mantle },
    --   TelescopePromptTitle = { bg = colors.pink, fg = colors.mantle },
    --   TelescopeResultsTitle = { fg = colors.mantle },
    --
    --   TelescopePreviewTitle = { bg = colors.green, fg = colors.mantle },
    -- }

    -- for hl, col in pairs(TelescopeColor) do
    --   vim.api.nvim_set_hl(0, hl, col)
    -- end
  end,
}
