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
          org_use_property_inheritance = true,
          org_deadline_warning_days = 7,
          org_cycle_separator_lines = 0,
          org_blank_before_new_entry = {
            heading = false,
            plain_list_item = false,
          },
          org_agenda_span = "week",
          org_todo_keywords = { 'TODO', 'NEXT', 'PEND', 'TEST', 'WARN', 'DONE' },
          org_todo_keyword_faces = {
            NEXT = ':foreground #89b4fa',
            PEND = ':foreground #eed49f',
            WARN = ':foreground #f5a97f',
            TEST = ':foreground #94e2d5',
          },
          ui = {
            agenda = {
              preview_window = {
                wrap = false, -- This option is set by default
                border = 'single'
              }
            }
          },
          mappings = {
            org_return_uses_meta_return = true,
            global = {
              org_agenda = "<leader>oA",
            },
            org = {
              org_refile = "<leader>oR",
              org_export = "<leader>oE",
              org_set_tags_command = "T",
              org_archive_subtree = '<leader>d'
            },
            agenda = {
              org_agenda_quit = "<C-w>",
              org_agenda_switch_to = "<Tab>",
              org_agenda_goto = "<CR>",
              org_agenda_priority = "p",
              org_agenda_priority_up = '+',
              org_agenda_priority_down = '-',
              -- org_agenda_archive = 'd',
              org_agenda_toggle_archive_tag = 'd',
              org_agenda_schedule = '<leader>s',
              org_agenda_add_note = '<leader>n',
              org_agenda_filter = '/',
              org_agenda_preview = 'L',
              org_agenda_show_help = '?',
              org_agenda_later = "<C-f>",
              org_agenda_set_tags = "T",
              org_agenda_goto_date = '<leader>d',
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
            -- j = {
            --   description = 'Daily',
            --   template = '\n*** %<%Y-%m-%d> %<%A>\n**** %U\n\n%?',
            --   target = '~/org/daily/%<%Y-%m>.org'
            -- },
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
                m = {
                  description = 'music',
                  template = [[
** TODO %^{Title} :personal:
  SCHEDULED: %^{SCHEDULED Date and Time}T
]],
                  target = '~/org/calendar.org',
                  headline = 'music'
                },
              },
            },
          },
          org_agenda_files = '~/org/**/*',
          org_default_notes_file = '~/org/index.org',
          org_agenda_custom_commands = {
            a = {
              description = 'All', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+NEXT-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'NEXT',
                },
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+TODO-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'TODO',
                },
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+WARN-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'WARNING',
                },
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+PEND-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'PENDING',
                },
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+DONE-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'DONE',
                },
              }
            },
            A = {
              description = 'Archive', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+NEXT+ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'NEXT',
                },
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+TODO+ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'TODO',
                },
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+WARN+ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'WARNING',
                },
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+PEND+ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'PENDING',
                },
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+DONE+ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'DONE',
                },
              }
            },
            n = {
              description = 'Next', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+NEXT-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'NEXT',
                },
              }
            },
            T = {
              description = 'Testing', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+TEST-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'TEST',
                },
              }
            },
            t = {
              description = 'Todo', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+TODO-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'TODO',
                },
              }
            },
            p = {
              description = 'Pending', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+PEND-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'PENDING',
                },
              }
            },
            w = {
              description = 'Warning', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+WARN-ARCHIVE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'WARNING',
                },
              }
            },
            d = {
              description = 'Done', -- Description shown in the prompt for the shortcut
              types = {
                {
                  type = 'tags_todo', -- Type can be agenda | tags | tags_todo
                  match = '/!+DONE',  --Same as providing a "Match:" for tags view <leader>oa + m, See: https://orgmode.org/manual/Matching-tags-and-properties.html
                  org_agenda_overriding_header = 'DONE',
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
      config = function()
        require("org-bullets").setup({
          symbols = {
            headlines = { '● ', '󰎦 ', '󰎩 ', '󰎬 ', '󰎮 ', '󰎰 ' },
            checkboxes = {
              -- error = { "x", "@error" },
              -- pending = { "", "@constant" },
              -- warning = { "!", "@comment.warning.gitcommit" },
              -- question = { "?", "@comment.warning.gitcommit" },
              done = { "✓", "@org.keyword.done" },
              todo = { " ", "@org.keyword.todo" },
            },
          }
        })
      end
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
