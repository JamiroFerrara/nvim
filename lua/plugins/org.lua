return {
  "chipsenkbeil/org-roam.nvim",
  tag = "0.2.0",
  ft = { 'org' },
  dependencies = {
    {
      "nvim-orgmode/orgmode",
      tag = "0.7.0",
      event = 'VeryLazy',
      -- ft = { 'org' },
      config = function()
        -- Setup orgmode
        require('orgmode').setup({
          org_agenda_files = '~/org/**/*',
          org_default_notes_file = '~/org/refile.org',
        })

        -- NOTE: If you are using nvim-treesitter with ~ensure_installed = "all"~ option
        -- add ~org~ to ignore_install
        -- require('nvim-treesitter.configs').setup({
        --   ensure_installed = 'all',
        --   ignore_install = { 'org' },
        -- })
      end,
    },
    {
      "lukas-reineke/headlines.nvim",
      dependencies = "nvim-treesitter/nvim-treesitter",
      config = true, -- or `opts = {}`
    },
    {
      "akinsho/org-bullets.nvim",
      opts = {},
    },
    {
      "eprislac/org-gcal-sync",
      dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-orgmode/orgmode",
        "jmbuhr/org-roam.nvim" -- optional
      },
      config = function()
        require("org-gcal-sync").setup({
          org_dirs = { "~/org/events" },
          enable_backlinks = true, -- requires org-roam
          auto_sync_on_save = true,

          -- Advanced features (optional)
          calendars = { "stiwiemayday@gmail.com", "3652dec984e222ff2640452ef7ddffd4b6f56f6f5c0b7b485d255b3eb91677c3@group.calendar.google.com" }, -- Add more calendars: { "primary", "work@company.com" }
          sync_recurring_events = true,
          conflict_resolution = "newest", -- "ask", "local", "remote", or "newest"
          show_sync_status = true,
          -- per_directory_calendars = { ["~/org/work"] = "work@company.com" },
          -- webhook_port = 8080,
        })
      end,
    }
  },
  config = function()
    require("org-roam").setup({
      mappings = {
        disable_all = true
      },
      directory = "~/org",
      -- optional
      -- org_files = {
      --   "~/org",
      -- }
    })
  end
}
