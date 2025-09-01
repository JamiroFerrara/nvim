return {
  'folke/snacks.nvim',
  -- enabled = not _G.NVIM_TERMINAL_ONLY,
  priority = 1000,
  event = 'VeryLazy',
  ---@type snacks.Config
  opts = {
    -- your configuration comes here
    -- or leave it empty to use the default settings
    -- refer to the configuration section below
    explorer = { enabled = true },
    quickfile = { enabled = true },
    bigfile = { enabled = true },
    dashboard = { enabled = true },
    indent = { enabled = true },
    input = { enabled = true },
    notifier = { enabled = true },
    zen = {
      -- You can add any `Snacks.toggle` id here.
      -- Toggle state is restored when the window is closed.
      -- Toggle config options are NOT merged.
      ---@type table<string, boolean>
      toggles = {
        dim = true,
        git_signs = false,
        mini_diff_signs = false,
        -- diagnostics = false,
        -- inlay_hints = false,
      },
      show = {
        statusline = false, -- can only be shown when using the global statusline
        tabline = false,
      },
      ---@type snacks.win.Config
      win = { style = 'zen' },
      --- Callback when the window is opened.
      ---@param win snacks.win
      on_open = function(win) end,
      --- Callback when the window is closed.
      ---@param win snacks.win
      on_close = function(win) end,
      --- Options for the `Snacks.zen.zoom()`
      ---@type snacks.zen.Config
      zoom = {
        toggles = {},
        show = { statusline = true, tabline = true },
        win = {
          backdrop = false,
          width = 0, -- full width
        },
      },
    },
  },
}
