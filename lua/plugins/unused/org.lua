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
        require('orgmode').setup({
          mappings = {
            org_return_uses_meta_return = true,
            global = {},
            org = {
              org_toggle_checkbox = "<CR>",
              org_global_cycle = "<leader>or",
              -- org_cycle = '<CR>' -- Header folding
              -- org_toggle_heading = "",
            },
            agenda = {
              org_agenda_switch_to = "<Tab>",
              org_agenda_goto = "<CR>",
              org_agenda_priority = "<leader>p",
              org_agenda_priority_up = '+',
              org_agenda_priority_down = '-',
              org_agenda_archive = '<BS>',
              org_agenda_schedule = '<leader>s',
              org_agenda_add_note = '<leader>n',
              org_agenda_filter = 'f',
              org_agenda_preview = 'L',
              org_agenda_show_help = '?',
            },
            capture = {
              org_capture_finalize = '<A-e>',
              org_capture_show_help = '?',
            },
            note = {
              org_note_finalize = '<A-e>'
            },
          },
          org_agenda_files = '~/org/**/*',
          org_default_notes_file = '~/org/index.org',
          org_agenda_custom_commands = {
            -- "c" is the shortcut that will be used in the prompt
            w = {
              description = 'Work View', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo',                       -- Type can be agenda | tags | tags_todo
                  match = '+PRIORITY="A"+work',             --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'High priority',
                  org_agenda_todo_ignore_deadlines = 'far', -- Ignore all deadlines that are too far in future (over org_deadline_warning_days). Possible values: all | near | far | past | future
                },
                {
                  type                              = 'agenda',
                  org_agenda_tag_filter_preset      = 'work', --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header      = 'Scheduled',
                  org_agenda_span                   = 'week', -- 'week' is default, so it's not necessary here, just an example
                  org_agenda_start_on_weekday       = 1,      -- Start on Monday
                  org_agenda_remove_tags            = false,  -- Do not show tags only for this view
                  org_agenda_todo_ignore_scheduled  = 'past', --FIX: Not working
                  org_agenda_skip_scheduled_if_done = false,
                },
                {
                  type = 'tags',
                  match = '+work', --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'Unscheduled',
                  org_agenda_todo_ignore_scheduled = 'all',
                },
              }
            },
            p = {
              description = 'Personal View', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo',                       -- Type can be agenda | tags | tags_todo
                  match = '+PRIORITY="A"+personal',         --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'High priority',
                  org_agenda_todo_ignore_deadlines = 'far', -- Ignore all deadlines that are too far in future (over org_deadline_warning_days). Possible values: all | near | far | past | future
                },
                {
                  type                              = 'agenda',
                  org_agenda_tag_filter_preset      = 'personal', --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header      = 'Scheduled',
                  org_agenda_span                   = 'week',     -- 'week' is default, so it's not necessary here, just an example
                  org_agenda_start_on_weekday       = 1,          -- Start on Monday
                  org_agenda_remove_tags            = false,      -- Do not show tags only for this view
                  org_agenda_todo_ignore_scheduled  = 'past',     --FIX: Not working
                  org_agenda_skip_scheduled_if_done = false,
                },
                {
                  type = 'tags',
                  match = '+personal', --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'Unscheduled',
                  org_agenda_todo_ignore_scheduled = 'all',
                },
              }
            },
          }
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
        vim.api.nvim_set_keymap("n", "<leader>od", "<cmd>OrgGcalDashboard<cr>", { noremap = true, silent = true })
        require("org-gcal-sync").setup({
          org_dirs = {
            "~/org/events",
            -- "~/org/gigs",
          },
          enable_backlinks = true, -- requires org-roam
          auto_sync_on_save = false,

          -- Advanced features (optional)
          calendars = { "stiwiemayday@gmail.com", "3652dec984e222ff2640452ef7ddffd4b6f56f6f5c0b7b485d255b3eb91677c3@group.calendar.google.com" }, -- Add more calendars: { "primary", "work@company.com" }
          sync_recurring_events = true,
          conflict_resolution = "newest",                                                                                                         -- "ask", "local", "remote", or "newest"
          show_sync_status = true,
          -- per_directory_calendars = {
          --   ["~/org/events"] = "stiwiemayday@gmail.com",
          --   ["~/org/gigs"] = "3652dec984e222ff2640452ef7ddffd4b6f56f6f5c0b7b485d255b3eb91677c3@group.calendar.google.com"
          -- },
          -- webhook_port = 8080,
        })
      end,
    }
  },
  config = function()
    require("org-roam").setup({
      mappings = {
        disable_all = false
      },
      directory = "~/org",
      -- optional
      -- org_files = {
      --   "~/org",
      -- }
    })
  end
}
