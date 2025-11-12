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
          org_hide_leading_stars = false, -- optional
          org_indent_mode = true,
          win_split_mode = "horizontal",
          org_deadline_warning_days = 7,
          org_cycle_separator_lines = 0,
          org_blank_before_new_entry = {
            heading = false,
            plain_list_item = false,
          },
          org_agenda_span = "week",
          -- FIX: Doesn't work with "t" mapping
          -- org_todo_keywords = { 'TODO', 'NEXT', 'DONE', 'PENDING' },
          -- org_todo_keyword_faces = {
          --   WAITING = ':foreground blue :weight bold',
          --   DELEGATED = ':background #FFFFFF :slant italic :underline on',
          --   TODO = ':background #000000 :foreground red', -- overrides builtin color for `TODO` keyword
          -- },
          mappings = {
            org_return_uses_meta_return = true,
            global = {},
            org = {
              org_refile = "<leader>oR",
            },
            agenda = {
              org_agenda_switch_to = "<Tab>",
              org_agenda_goto = "<CR>",
              org_agenda_priority = "<leader>p",
              org_agenda_priority_up = '+',
              org_agenda_priority_down = '-',
              org_agenda_archive = 'd',
              org_agenda_schedule = '<leader>s',
              org_agenda_add_note = '<leader>n',
              org_agenda_filter = '/',
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
          org_capture_templates = {
            -- FIX:
            j = {
              description = 'Daily',
              template = '\n*** %<%Y-%m-%d> %<%A>\n**** %U\n\n%?',
              target = '~/org/daily/%<%Y-%m>.org'
            },
            t = {
              description = 'Todo',
              subtemplates = {
                w = {
                  description = 'work',
                  target = '~/org/todo.org',
                  headline = 'work',
                  template = [[
* TODO %^{Title} :work:
]],
                },
                p = {
                  description = 'personal',
                  target = '~/org/todo.org',
                  headline = 'personal',
                  template = [[
* TODO %^{Title} :personal:
]],
                },
                f = {
                  description = 'finance',
                  target = '~/org/todo.org',
                  headline = 'finance',
                  template = [[
* TODO %^{Title} :finance:
                  ]],
                },
                m = {
                  description = 'music',
                  target = '~/org/todo.org',
                  headline = 'music',
                  template = [[
* TODO %^{Title} :music:
                  ]],
                }
              }
            },
            e = {
              description = 'Event',
              subtemplates = {
                w = {
                  description = 'work',
                  template = [[
** TODO %^{Title} :work:
  SCHEDULED: %^{SCHEDULED Date and Time}T
]],
                  target = '~/org/calendar.org',
                  headline = 'work'
                },
                p = {
                  description = 'personal',
                  template = [[
** TODO %^{Title} :personal:
  SCHEDULED: %^{SCHEDULED Date and Time}T
]],
                  target = '~/org/calendar.org',
                  headline = 'personal'
                },
              },
            },
          },
          org_agenda_files = '~/org/**/*',
          org_default_notes_file = '~/org/index.org',
          org_agenda_custom_commands = {
            -- "c" is the shortcut that will be used in the prompt
            w = {
              description = 'Work View', -- Description shown in the prompt for the shortcut
              types = {
                -- {
                --   type = 'tags_todo',                       -- Type can be agenda | tags | tags_todo
                --   match = '+PRIORITY="A"+work',             --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                --   org_agenda_overriding_header = 'High priority',
                --   org_agenda_todo_ignore_deadlines = 'far', -- Ignore all deadlines that are too far in future (over org_deadline_warning_days). Possible values: all | near | far | past | future
                -- },
                {
                  type = 'tags',
                  match = '+work', --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'Unscheduled',
                  org_agenda_todo_ignore_scheduled = 'all',
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
      "akinsho/org-bullets.nvim",
      opts = {},
    },
    -- FIX: Slow as shit
    -- {
    --   "eprislac/org-gcal-sync",
    --   dependencies = {
    --     "nvim-lua/plenary.nvim",
    --     "nvim-orgmode/orgmode",
    --     "jmbuhr/org-roam.nvim" -- optional
    --   },
    --   config = function()
    --     vim.api.nvim_set_keymap("n", "<leader>od", "<cmd>OrgGcalDashboard<cr>", { noremap = true, silent = true })
    --     require("org-gcal-sync").setup({
    --       org_dirs = {
    --         "~/org/gcal",
    --         -- "~/org/calendar.org",
    --       },
    --       enable_backlinks = true, -- requires org-roam
    --       auto_sync_on_save = false,
    --       background_sync_interval = 600000,
    --
    --       -- Advanced features (optional)
    --       calendars = { "stiwiemayday@gmail.com", "3652dec984e222ff2640452ef7ddffd4b6f56f6f5c0b7b485d255b3eb91677c3@group.calendar.google.com" }, -- Add more calendars: { "primary", "work@company.com" }
    --       sync_recurring_events = true,
    --       conflict_resolution = "newest",                                                                                                         -- "ask", "local", "remote", or "newest"
    --       show_sync_status = true,
    --       -- per_directory_calendars = {
    --       --   ["~/org/events"] = "stiwiemayday@gmail.com",
    --       --   ["~/org/gigs"] = "3652dec984e222ff2640452ef7ddffd4b6f56f6f5c0b7b485d255b3eb91677c3@group.calendar.google.com"
    --       -- },
    --       -- webhook_port = 8080,
    --     })
    --   end,
    -- }
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
