return {
  "hrsh7th/cmp-cmdline",
  enabled = true,
  event = {
    "BufReadPost",
    "BufNewFile",
    "BufWritePre",
  },
  dependencies = {
    "hrsh7th/nvim-cmp",
  },
  config = function()
    local cmp = require("cmp")

    -- Setup for search (`/` and `?`)
    -- Setup for command mode (`:`)
    cmp.setup.cmdline(":", {
      mapping = cmp.mapping.preset.cmdline({
        ["<C-j>"] = {
          c = function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            else
              fallback()
            end
          end
        },
        ["<C-k>"] = {
          c = function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            else
              fallback()
            end
          end
        }
      }),
      sources = cmp.config.sources({
        { name = "path" },
      }, {
        { name = "cmdline" },
      }),
    })
  end,
}

