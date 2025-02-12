return {
  'folke/snacks.nvim',
  opts = {
    picker = {
      prompt = ' ',
      sources = {},
      focus = 'input',
      layout = {
        cycle = true,
        --- Use the default layout or vertical if the window is too narrow
        preset = function()
          return vim.o.columns >= 120 and 'default' or 'vertical'
        end,
      },
      ---@class snacks.picker.matcher.Config
      matcher = {
        fuzzy = true, -- use fuzzy matching
        smartcase = true, -- use smartcase
        ignorecase = true, -- use ignorecase
        sort_empty = false, -- sort results when the search string is empty
        filename_bonus = true, -- give bonus for matching file names (last part of the path)
        file_pos = true, -- support patterns like `file:line:col` and `file:line`
        -- the bonusses below, possibly require string concatenation and path normalization,
        -- so this can have a performance impact for large lists and increase memory usage
        cwd_bonus = false, -- give bonus for matching files in the cwd
        frecency = true, -- frecency bonus
        history_bonus = false, -- give more weight to chronological order
      },
      sort = {
        -- default sort is by score, text length and index
        fields = { 'score:desc', '#text', 'idx' },
      },
      ui_select = true, -- replace `vim.ui.select` with the snacks picker
      ---@class snacks.picker.formatters.Config
      formatters = {
        text = {
          ft = nil, ---@type string? filetype for highlighting
        },
        file = {
          filename_first = false, -- display filename before the file path
          truncate = 40, -- truncate the file path to (roughly) this length
          filename_only = false, -- only show the filename
          icon_width = 2, -- width of the icon (in characters)
        },
        selected = {
          show_always = false, -- only show the selected column when there are multiple selections
          unselected = true, -- use the unselected icon for unselected items
        },
        severity = {
          icons = true, -- show severity icons
          level = false, -- show severity level
          ---@type "left"|"right"
          pos = 'left', -- position of the diagnostics
        },
      },
      ---@class snacks.picker.previewers.Config
      previewers = {
        git = {
          native = false, -- use native (terminal) or Neovim for previewing git diffs and commits
        },
        file = {
          max_size = 1024 * 1024, -- 1MB
          max_line_length = 500, -- max line length
          ft = nil, ---@type string? filetype for highlighting. Use `nil` for auto detect
        },
        man_pager = nil, ---@type string? MANPAGER env to use for `man` preview
      },
      ---@class snacks.picker.jump.Config
      jump = {
        jumplist = true, -- save the current position in the jumplist
        tagstack = false, -- save the current position in the tagstack
        reuse_win = false, -- reuse an existing window if the buffer is already open
        close = true, -- close the picker when jumping/editing to a location (defaults to true)
        match = false, -- jump to the first match position. (useful for `lines`)
      },
      toggles = {
        follow = 'f',
        hidden = '<A-h>',
        ignored = 'i',
        modified = 'm',
        regex = { icon = 'R', value = false },
      },
      win = {
        -- input window
        input = {
          keys = {
            -- to close the picker on ESC instead of going to normal mode,
            -- add the following keymap to your config
            ['<Esc>'] = { 'close', mode = { 'n', 'i' } },
            ['kj'] = { 'close', mode = { 'n', 'i' } },
            ['/'] = 'toggle_focus',
            ['<c-n>'] = { 'history_forward', mode = { 'i', 'n' } },
            ['<c-p>'] = { 'history_back', mode = { 'i', 'n' } },
            ['<C-c>'] = { 'close', mode = 'i' },
            ['<C-w>'] = { '<c-s-w>', mode = { 'i' }, expr = true, desc = 'delete word' },
            ['<CR>'] = { 'confirm', mode = { 'n', 'i' } },
            ['<Down>'] = { 'list_down', mode = { 'i', 'n' } },
            ['<S-CR>'] = { { 'pick_win', 'jump' }, mode = { 'n', 'i' } },
            ['<S-Tab>'] = { 'select_and_prev', mode = { 'i', 'n' } },
            ['<Tab>'] = { 'select_and_next', mode = { 'i', 'n' } },
            ['<Up>'] = { 'list_up', mode = { 'i', 'n' } },
            ['<a-d>'] = { 'inspect', mode = { 'n', 'i' } },
            ['<a-f>'] = { 'toggle_follow', mode = { 'i', 'n' } },
            ['<a-h>'] = { 'toggle_hidden', mode = { 'i', 'n' } },
            ['<a-i>'] = { 'toggle_ignored', mode = { 'i', 'n' } },
            ['<a-m>'] = { 'toggle_maximize', mode = { 'i', 'n' } },
            ['<a-p>'] = { 'toggle_preview', mode = { 'i', 'n' } },
            ['<a-w>'] = { 'cycle_win', mode = { 'i', 'n' } },
            ['<c-a>'] = { 'select_all', mode = { 'n', 'i' } },
            ['<c-b>'] = { 'preview_scroll_up', mode = { 'i', 'n' } },
            ['<c-d>'] = { 'list_scroll_down', mode = { 'i', 'n' } },
            ['<c-f>'] = { 'preview_scroll_down', mode = { 'i', 'n' } },
            ['<c-g>'] = { 'toggle_live', mode = { 'i', 'n' } },
            ['<c-j>'] = { 'list_down', mode = { 'i', 'n' } },
            ['<a-j>'] = { 'list_down', mode = { 'i', 'n' } },
            ['<c-k>'] = { 'list_up', mode = { 'i', 'n' } },
            ['<a-k>'] = { 'list_up', mode = { 'i', 'n' } },
            ['<c-q>'] = { 'qflist', mode = { 'i', 'n' } },
            ['<c-v>'] = { 'edit_split', mode = { 'i', 'n' } },
            ['<c-u>'] = { 'list_scroll_up', mode = { 'i', 'n' } },
            ['<c-s>'] = { 'edit_vsplit', mode = { 'i', 'n' } },
            ['<c-z>h'] = { 'layout_left', mode = { 'i', 'n' } },
            ['<c-z><c-h>'] = { 'layout_left', mode = { 'i', 'n' } },
            ['<c-z>j'] = { 'layout_bottom', mode = { 'i', 'n' } },
            ['<c-z><c-j>'] = { 'layout_bottom', mode = { 'i', 'n' } },
            ['<c-z>k'] = { 'layout_top', mode = { 'i', 'n' } },
            ['<c-z><c-k>'] = { 'layout_top', mode = { 'i', 'n' } },
            ['<c-z>l'] = { 'layout_right', mode = { 'i', 'n' } },
            ['<c-z><c-l>'] = { 'layout_right', mode = { 'i', 'n' } },
            ['?'] = 'toggle_help_input',
            ['G'] = 'list_bottom',
            ['gg'] = 'list_top',
            ['j'] = 'list_down',
            ['k'] = 'list_up',
            ['q'] = 'close',
          },
          b = {
            minipairs_disable = true,
          },
        },
        -- result list window
        list = {
          keys = {
            ['/'] = 'toggle_focus',
            ['<2-LeftMouse>'] = 'confirm',
            ['<CR>'] = 'confirm',
            ['<Down>'] = 'list_down',
            ['<Esc>'] = 'close',
            ['<S-CR>'] = { { 'pick_win', 'jump' } },
            ['<S-Tab>'] = { 'select_and_prev', mode = { 'n', 'x' } },
            ['<Tab>'] = { 'select_and_next', mode = { 'n', 'x' } },
            ['<Up>'] = 'list_up',
            ['<a-d>'] = 'inspect',
            ['<a-f>'] = 'toggle_follow',
            ['<a-h>'] = 'toggle_hidden',
            ['<a-i>'] = 'toggle_ignored',
            ['<a-m>'] = 'toggle_maximize',
            ['<a-p>'] = 'toggle_preview',
            ['<a-w>'] = 'cycle_win',
            ['<c-a>'] = 'select_all',
            ['<c-b>'] = 'preview_scroll_up',
            ['<c-d>'] = 'list_scroll_down',
            ['<c-f>'] = 'preview_scroll_down',
            ['<c-j>'] = 'list_down',
            ['<c-k>'] = 'list_up',
            ['<c-n>'] = 'list_down',
            ['<c-p>'] = 'list_up',
            ['<c-s>'] = 'edit_split',
            ['<c-u>'] = 'list_scroll_up',
            ['<c-v>'] = 'edit_vsplit',
            ['<c-z>h'] = { 'layout_left', mode = { 'i', 'n' } },
            ['<c-z><c-h>'] = { 'layout_left', mode = { 'i', 'n' } },
            ['<c-z>j'] = { 'layout_bottom', mode = { 'i', 'n' } },
            ['<c-z><c-j>'] = { 'layout_bottom', mode = { 'i', 'n' } },
            ['<c-z>k'] = { 'layout_top', mode = { 'i', 'n' } },
            ['<c-z><c-k>'] = { 'layout_top', mode = { 'i', 'n' } },
            ['<c-z>l'] = { 'layout_right', mode = { 'i', 'n' } },
            ['<c-z><c-l>'] = { 'layout_right', mode = { 'i', 'n' } },
            ['?'] = 'toggle_help_list',
            ['G'] = 'list_bottom',
            ['gg'] = 'list_top',
            ['i'] = 'focus_input',
            ['j'] = 'list_down',
            ['k'] = 'list_up',
            ['q'] = 'close',
            ['zb'] = 'list_scroll_bottom',
            ['zt'] = 'list_scroll_top',
            ['zz'] = 'list_scroll_center',
          },
          wo = {
            conceallevel = 2,
            concealcursor = 'nvc',
          },
        },
        -- preview window
        preview = {
          keys = {
            ['<Esc>'] = 'close',
            ['q'] = 'close',
            ['i'] = 'focus_input',
            ['<ScrollWheelDown>'] = 'list_scroll_wheel_down',
            ['<ScrollWheelUp>'] = 'list_scroll_wheel_up',
            ['<a-w>'] = 'cycle_win',
          },
        },
      },
    },
    explorer = {},
  },
  keys = {
    -- {
    --   'f',
    --   function()
    --     Snacks.picker.lines {
    --       layout = {
    --         preview = 'main',
    --         layout = {
    --           box = 'vertical',
    --           backdrop = false,
    --           width = 0,
    --           height = 0.3,
    --           position = 'bottom',
    --           border = 'top',
    --           title = ' {title} {live} {flags}',
    --           title_pos = 'left',
    --           { win = 'input', height = 1, border = 'bottom' },
    --           {
    --             box = 'horizontal',
    --             { win = 'list', border = 'none' },
    --             { win = 'preview', title = '{preview}', width = 0.6, border = 'left' },
    --           },
    --         },
    --       },
    --       on_close = function(item)
    --         local pattern = item.input.filter.pattern
    --         vim.fn.setreg('/', pattern)
    --       end,
    --       matcher = {
    --         fuzzy = false,
    --         smartcase = true,
    --         ignorecase = true,
    --         sort_empty = false,
    --       },
    --       -- FIX:
    --       -- on_change = function(picker, item)
    --       --   local filtered_items = picker.items(picker) -- Get the filtered list of items
    --       --   if #filtered_items > 0 then
    --       --     local first_item = filtered_items[1]
    --       --     print(first_item.text, first_item.pos[1])
    --       --     picker.list.set_selected(picker.list, first_item)
    --       --   end
    --       -- end,
    --       transform = function(item, ctx) -- NOTE: This searches only from current line down
    --         local line_nr = vim.api.nvim_win_get_cursor(0)[1]
    --         if item.pos[1] < line_nr then
    --           return false
    --         end
    --       end,
    --       sort = {
    --         fields = {
    --           'lnum',
    --         },
    --       },
    --     }
    --   end,
    --   desc = 'Buffer Lines',
    -- },
    {
      '<C-f>',
      function()
        Snacks.picker.lines {
          layout = {
            preview = 'main',
            layout = {
              box = 'vertical',
              backdrop = false,
              width = 0,
              height = 0.3,
              position = 'bottom',
              border = 'top',
              title = ' {title} {live} {flags}',
              title_pos = 'left',
              { win = 'input', height = 1, border = 'bottom' },
              {
                box = 'horizontal',
                { win = 'list', border = 'none' },
                { win = 'preview', title = '{preview}', width = 0.6, border = 'left' },
              },
            },
          },
          on_close = function(item)
            local pattern = item.input.filter.pattern
            vim.fn.setreg('/', pattern)
          end,
          matcher = {
            fuzzy = false,
            smartcase = true,
            ignorecase = true,
            sort_empty = false,
          },
          sort = {
            fields = {
              'lnum',
            },
          },
        }
      end,
      desc = 'Buffer Lines',
    },

    -- Top Pickers & Explorer
    {
      '<leader>,',
      function()
        Snacks.picker.buffers()
      end,
      desc = 'Buffers',
    },
    {
      '<leader>:',
      function()
        Snacks.picker.command_history()
      end,
      desc = 'Command History',
    },
    {
      '<leader>n',
      function()
        Snacks.picker.notifications()
      end,
      desc = 'Notification History',
    },
    {
      '<leader>e',
      function()
        Snacks.explorer()
      end,
      desc = 'File Explorer',
    },
    -- find
    {
      '<leader>fb',
      function()
        Snacks.picker.buffers()
      end,
      desc = 'Buffers',
    },
    {
      '<leader>fc',
      function()
        Snacks.picker.files { cwd = vim.fn.stdpath 'config' }
      end,
      desc = 'Find Config File',
    },
    {
      '<leader><space>',
      function()
        Snacks.picker.files { layout = 'ivy', matcher = { frecency = true } }
      end,
      desc = 'Find Files',
    },
    -- { "<leader>ff", function() Snacks.picker.files({layout = "ivy", matcher = {frecency = true}}) end, desc = "Find Files" },
    {
      '<C-p>',
      function()
        Snacks.picker.files { layout = 'ivy', matcher = { frecency = true } }
      end,
      desc = 'Find Files',
    },
    -- {
    --   '<leader>fw',
    --   function()
    --     Snacks.picker.grep { layout = 'ivy', need_search = false, limit = 30, matcher = { fuzzy = false, sort_empty = false } }
    --   end,
    --   desc = 'Grep',
    -- },
    {
      '<leader>fg',
      function()
        Snacks.picker.git_files()
      end,
      desc = 'Find Git Files',
    },
    {
      '<leader>fp',
      function()
        Snacks.picker.projects()
      end,
      desc = 'Projects',
    },
    {
      '<leader>fr',
      function()
        Snacks.picker.recent()
      end,
      desc = 'Recent',
    },
    -- git
    {
      '<leader>gb',
      function()
        Snacks.picker.git_branches { layout = 'ivy' }
      end,
      desc = 'Git Branches',
    },
    {
      '<leader>gl',
      function()
        Snacks.picker.git_log { layout = 'ivy' }
      end,
      desc = 'Git Log',
    },
    {
      '<leader>gL',
      function()
        Snacks.picker.git_log_line { layout = 'ivy' }
      end,
      desc = 'Git Log Line',
    },
    {
      '<leader>gs',
      function()
        Snacks.picker.git_status { layout = 'ivy' }
      end,
      desc = 'Git Status',
    },
    {
      '<leader>gS',
      function()
        Snacks.picker.git_stash { layout = 'ivy' }
      end,
      desc = 'Git Stash',
    },
    {
      '<leader>gd',
      function()
        Snacks.picker.git_diff { layout = 'ivy' }
      end,
      desc = 'Git Diff (Hunks)',
    },
    {
      '<leader>gf',
      function()
        Snacks.picker.git_log_file { layout = 'ivy' }
      end,
      desc = 'Git Log File',
    },
    -- Grep
    {
      '<leader>ff',
      function()
        Snacks.picker.lines()
      end,
      desc = 'Buffer Lines',
    },
    {
      '<leader>sB',
      function()
        Snacks.picker.grep_buffers()
      end,
      desc = 'Grep Open Buffers',
    },
    {
      '<leader>sg',
      function()
        Snacks.picker.grep()
      end,
      desc = 'Grep',
    },
    {
      '<leader>fc',
      function()
        Snacks.picker.grep_word { layout = 'ivy' }
      end,
      desc = 'Visual selection or word',
      mode = { 'n', 'x' },
    },
    -- search
    {
      '<leader>s"',
      function()
        Snacks.picker.registers()
      end,
      desc = 'Registers',
    },
    {
      '<leader>s/',
      function()
        Snacks.picker.search_history()
      end,
      desc = 'Search History',
    },
    {
      '<leader>sa',
      function()
        Snacks.picker.autocmds()
      end,
      desc = 'Autocmds',
    },
    {
      '<leader>sc',
      function()
        Snacks.picker.command_history()
      end,
      desc = 'Command History',
    },
    {
      '<leader>sC',
      function()
        Snacks.picker.commands()
      end,
      desc = 'Commands',
    },
    {
      '<leader>sd',
      function()
        Snacks.picker.diagnostics()
      end,
      desc = 'Diagnostics',
    },
    {
      '<leader>sD',
      function()
        Snacks.picker.diagnostics_buffer()
      end,
      desc = 'Buffer Diagnostics',
    },
    {
      '<leader>sh',
      function()
        Snacks.picker.help()
      end,
      desc = 'Help Pages',
    },
    {
      '<leader>sH',
      function()
        Snacks.picker.highlights()
      end,
      desc = 'Highlights',
    },
    {
      '<leader>si',
      function()
        Snacks.picker.icons()
      end,
      desc = 'Icons',
    },
    {
      '<leader>sj',
      function()
        Snacks.picker.jumps()
      end,
      desc = 'Jumps',
    },
    {
      '<leader>sk',
      function()
        Snacks.picker.keymaps()
      end,
      desc = 'Keymaps',
    },
    {
      '<leader>sl',
      function()
        Snacks.picker.picker_layouts()
      end,
      desc = 'Pickers list',
    },
    {
      '<leader>sm',
      function()
        Snacks.picker.marks()
      end,
      desc = 'Marks',
    },
    {
      '<leader>sM',
      function()
        Snacks.picker.man()
      end,
      desc = 'Man Pages',
    },
    {
      '<leader>sp',
      function()
        Snacks.picker.lazy()
      end,
      desc = 'Search for Plugin Spec',
    },
    {
      '<leader>fq',
      function()
        Snacks.picker.qflist { layout = 'bottom' }
      end,
      desc = 'Quickfix List',
    },
    {
      '<leader>sR',
      function()
        Snacks.picker.resume()
      end,
      desc = 'Resume',
    },
    {
      '<leader>su',
      function()
        Snacks.picker.undo()
      end,
      desc = 'Undo History',
    },
    {
      '<leader>uC',
      function()
        Snacks.picker.colorschemes()
      end,
      desc = 'Colorschemes',
    },
    -- LSP
    {
      'gd',
      function()
        Snacks.picker.lsp_definitions { layout = 'ivy' }
      end,
      desc = 'Goto Definition',
    },
    {
      'gD',
      function()
        Snacks.picker.lsp_declarations { layout = 'ivy' }
      end,
      desc = 'Goto Declaration',
    },
    {
      'gr',
      function()
        Snacks.picker.lsp_references { layout = 'ivy' }
      end,
      nowait = true,
      desc = 'References',
    },
    {
      'gI',
      function()
        Snacks.picker.lsp_implementations { layout = 'ivy' }
      end,
      desc = 'Goto Implementation',
    },
    {
      'gy',
      function()
        Snacks.picker.lsp_type_definitions { layout = 'ivy' }
      end,
      desc = 'Goto T[y]pe Definition',
    },
    -- {
    --   '<leader>ss',
    --   function()
    --     Snacks.picker.lsp_symbols()
    --   end,
    --   desc = 'LSP Symbols',
    -- },
    -- {
    --   '<leader>sS',
    --   function()
    --     Snacks.picker.lsp_workspace_symbols()
    --   end,
    --   desc = 'LSP Workspace Symbols',
    -- },
  },
}
