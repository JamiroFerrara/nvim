return {
  -- Normal Mode
  n = {
    -- DEV
    ['<leader>np'] = { '<cmd>Neopostman<CR>', desc = 'Neopostman' },
    ['<leader>nc'] = { '<cmd>ChromeNetwork<CR>', desc = 'Neopostman' },
    ['<leader>lp'] = { '<cmd>Lazy profile<CR>', desc = 'Shift right' },
    ['<leader>ji'] = { '<cmd>Neojira<cr>' },
    ['<leader>jq'] = { '<cmd>JqFile<CR>', desc = 'Shift right' },
    ['<leader>cn'] = { '<cmd>ChromeNetwork<cr>', desc = 'Open Chrome Network plugin' },

    ['<C-r>'] = { "<cmd>silent !tmux split-window -v -p 50 'source ~/.zshrc && run_script'<CR>", desc = "Open split, source .zshrc, and run the script" },

    -- inline function for formatting
    ["<leader>fb"] =
        function()
          pcall(vim.api.nvim_command, "doautocmd User event_conform")
          require("conform").format { async = true, lsp_fallback = true }
        end,

    ["<leader>ii"] =
        function()
          pcall(vim.api.nvim_command, "doautocmd User event_toggler")
          require("nvim-toggler").toggle()
        end,

    -- Basic Indentation
    ['<leader>ss'] = { '<cmd>luafile $MYVIMRC<CR>', desc = 'Shift right' },
    ['>'] = { '>>', desc = 'Shift right' },
    ['<'] = { '<<', desc = 'Shift left' },
    ['à'] = { '0', desc = 'Letter a with grave accent' },
    ['e'] = { 'E' },
    ['<A-n>'] = { '*', desc = 'Follow' },

    -- Marks
    ['m'] = { "'", desc = 'Follow' },
    ['<leader>fml'] = { '<cmd>CellularAutomaton make_it_rain<CR>', desc = 'Follow' },

    -- Leader Shortcuts
    ['<leader>sf'] = { ':%s/\\\\n/\\r/g', desc = 'Search and replace newlines' },

    -- ['<leader>e'] = { '<cmd>lua require("snacks").explorer()<cr>', desc = 'Toggle Neotree' },
    -- ['<C-e>'] = { '<cmd>lua require("snacks").explorer()<cr>', desc = 'Toggle Neotree' },

    ['<leader>lg'] = { '<cmd>lua os.execute("tmux neww lazygit")<cr>', desc = 'Open lazygit in a new tmux window' },
    ['<leader>dB'] = { '<cmd>DBUI<cr>', desc = 'Open DAP UI' },
    ['<leader>c'] = { '<cmd>lua require("Comment.api").toggle.linewise.current()<cr>', desc = 'Toggle comment' },
    ['cc'] = { '<cmd>lua require("Comment.api").toggle.linewise.current()<cr>', desc = 'Toggle comment' },
    ['<leader>mp'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make publish; tmux select-pane -U")<CR>', desc = 'Make publish' },
    ['<leader>md'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make down; tmux select-pane -U")<CR>', desc = 'Make publish' },
    ['<leader>mr'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make run; tmux select-pane -U")<CR>', desc = 'Make run' },
    ['<leader>mb'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make build; tmux select-pane -U")<CR>', desc = 'Make build' },
    ['<A-b>'] = { '<cmd>terminal $SHELL -c "make build; $SHELL"<CR>', desc = 'Make build' },
    ['<A-y>'] = { '<cmd>terminal $SHELL -c "make start; $SHELL"<CR>', desc = 'Make build' },
    ['<leader>mt'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make test; tmux select-pane -U")<CR>', desc = 'Make test' },
    ['<leader>ml'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make local; tmux select-pane -U")<CR>', desc = 'Make local' },
    ['<leader>ms'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make start; tmux select-pane -U")<CR>', desc = 'Make start' },
    ['<leader>mw'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make watch; tmux select-pane -U")<CR><cmd>DapContinue<cr>', desc = 'Make watch and continue', },
    ['<leader>yy'] = { 'GVggy<cmd>q!<CR>', desc = 'Yank all and quit' },
    ['<leader>tt'] = { '<cmd>TransparentToggle<cr>', desc = 'Toggle transparency' },
    ['<leader>at'] = { '<cmd>AerialToggle!<CR>', desc = 'Toggle Aerial' },
    ['mt'] = { '<cmd>e TODO.md<cr>', desc = 'Toggle Aerial' },

    ['<leader>x'] = { '<cmd>.!sh<CR>', desc = 'Execute line under cursor' },

    ['<leader>fw'] = { "<cmd>lua require'telescope.builtin'.live_grep(GET_IVY())<cr>" },
    ['<C-g>'] = { "<cmd>lua require'telescope.builtin'.live_grep(GET_IVY())<cr>" },

    ['vap'] = { 'vip' },

    --TODO: Obsidian Commands
    --Theese are the obsidian related commands, but with org mode now need to
    --figure out what to actually do with them.
    -- ['<leader>ob'] = { '<cmd>ObsidianBacklinks<cr>' },
    -- ['<leader>ot'] = { '<cmd>ObsidianToday<cr>' },
    -- ['<leader>oT'] = { '<cmd>ObsidianTomorrow<cr>' },
    -- ['<leader>oy'] = { '<cmd>ObsidianYesterday<cr>' },

    -- Org commands
    ['<leader>ot'] = { '<cmd>lua require("helpers.org-menu"):_open_todo_client_submenu()<cr>' },
    ['<leader>oa'] = { '<cmd>lua require("helpers.org-menu"):open_custom_menu()<cr>' },

    -- TMUX Commands
    ['<leader>th'] = {
      '<cmd>lua os.execute("tmux if-shell \\"[ $(tmux list-panes | wc -l) -eq 1 ]\\" \\"split-window -v -l 10\\" \\"resize-pane -Z\\"")<CR>',
      desc = 'toggle term bottom',
    },
    ['<A-t>'] = { '<cmd>term<cr>', desc = 'Follow' },
    ['<C-t>'] = {
      '<cmd>lua os.execute("tmux if-shell \\"[ $(tmux list-panes | wc -l) -eq 1 ]\\" \\"split-window -v -l 10\\" \\"resize-pane -Z; select-pane -D\\"")<CR>',
      desc = 'toggle term bottom',
    },
    -- ['<A-m>'] = {
    --   '<cmd>lua os.execute("tmux if-shell \\"[ $(tmux list-panes | wc -l) -eq 1 ]\\" \\"split-window -v -l 10\\" \\"resize-pane -Z; select-pane -D\\" && tmux send-keys \'m\' Enter")<CR>',
    --   desc = 'toggle term bottom and run m',
    -- },
    ['<leader>ap'] = { '<cmd>lua os.execute("/home/jferrara/.scripts/v-script.sh")<CR>', desc = 'toggle term bottom' },

    -- Git Commands
    ['<leader>gj'] = { '<cmd>lua require("gitsigns").next_hunk()<cr>' },
    ['<leader>gk'] = { '<cmd>lua require("gitsigns").prev_hunk()<cr>' },
    ['gj'] = { '<cmd>lua require("gitsigns").nav_hunk("next", { navigation_message = false })<cr>' },
    ['gk'] = { '<cmd>lua require("gitsigns").nav_hunk("prev", { navigation_message = false })<cr>' },
    ['<leader>gp'] = { '<cmd>lua require("gitsigns").preview_hunk()<cr>' },
    ['<leader>gh'] = { '<cmd>lua require("gitsigns").reset_hunk()<cr>' },
    ['gh'] = { '<cmd>lua require("gitsigns").reset_hunk()<cr>' },
    ['<leader>gr'] = { '<cmd>lua require("gitsigns").reset_buffer()<cr>' },
    ['<leader>gs'] = { '<cmd>lua require("gitsigns").stage_hunk()<cr>' },
    ['<leader>gu'] = { '<cmd>lua require("gitsigns").undo_stage_hunk()<cr>' },
    ['<leader>gd'] = { '<cmd>lua require("gitsigns").diffthis()<cr>' },

    -- Quick Actions
    ['<A-o>'] = { '<C-o>', desc = '' },
    ['<A-i>'] = { '<C-i>', desc = '' },
    -- ['<C-o>'] = { '<C-o>', desc = '' },
    ['<C-o>'] = { '<cmd>bprev<cr>', desc = 'Follow' },
    ['<C-i>'] = { '<C-i>', desc = '' },

    -- Text Objects
    ['ciu'] = { 'ci{' },
    ['diu'] = { 'di{' },
    ['viu'] = { 'vi{' },
    ['cau'] = { 'ca{' },
    ['dau'] = { 'da{' },
    ['vau'] = { 'va{' },
    ['ci2'] = { 'ci"' },
    ['di2'] = { 'ci"' },
    ['vi2'] = { 'vi"' },
    ['ca2'] = { 'ca"' },
    ['da2'] = { 'ca"' },
    ['va2'] = { 'va"' },
    ['cij'] = { 'ci[' },
    ['dij'] = { 'di[' },
    ['vij'] = { 'vi[' },
    ['caj'] = { 'ca[' },
    ['daj'] = { 'da[' },
    ['vaj'] = { 'va[' },
    ['ci8'] = { 'ci(' },
    ['di8'] = { 'di(' },
    ['vi8'] = { 'vi(' },
    ['ca8'] = { 'ca(' },
    ['da8'] = { 'da(' },
    ['va8'] = { 'va(' },

    ['<leader>ai'] = { '<cmd>Opencode<CR>' },
    ['<leader>aa'] = { '<cmd>GpChatNew vsplit<CR>' },

    ['<leader>av'] = { '<cmd>lua require("user.helpers").visualModeAi()<CR>' },
    ['<leader>am'] = { '<cmd>lua require("user.helpers").apiMockAi()<CR>' },
    ['<leader>at'] = { '<cmd>lua require("user.helpers").cs2ts()<CR>' },

    -- Harpoon
    ['<leader>m'] = { '<cmd>lua require("harpoon.mark").add_file()<cr>' },
    ['<leader>M'] = { '<cmd>lua require("harpoon.ui").toggle_quick_menu()<cr>' },
    ['<leader>1'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>' },
    ['<leader>2'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>' },
    ['<leader>3'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>' },
    ['<leader>4'] = { '<cmd>lua require("harpoon.ui").nav_file(4)<cr>' },
    ['<leader>5'] = { '<cmd>lua require("harpoon.ui").nav_file(5)<cr>' },
    ['<leader>6'] = { '<cmd>lua require("harpoon.ui").nav_file(6)<cr>' },
    ['<leader>7'] = { '<cmd>lua require("harpoon.ui").nav_file(7)<cr>' },

    ['{'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>' },
    ['}'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>' },
    ['+'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>' },

    -- Other
    ['|'] = { '1' },
    ['?'] = { '2' },
    ['&'] = { '3' },
    ['/'] = { '4' },
    ['N'] = { 'Nzzzv' },

    ['U'] = { ':redo<cr>' },
    ['Y'] = { 'y$' },
    ['n'] = { 'nzzzv' },
    ['J'] = { '<C-d>' },
    ['K'] = { '<C-u>' },

    ['<leader>j'] = { '}' },
    ['<leader>k'] = { '{' },

    ['ç'] = { 'J' },
    ['f'] = { '/' },
    ['F'] = { "<cmd>lua require('flash').jump()<cr>" },
    ['cp'] = { "<cmd>let @+ = expand('%:p')<cr>" },

    ['<leader>ac'] = { '<cmd>Copilot<CR>', desc = 'Complete code' },

    ['<leader>or'] = { "zR<cmd>lua require('helpers.markdown').fold_headings_of_level(3)<cr>" },
    ['<leader>oe'] = { "zR<cmd>lua require('helpers.markdown').fold_headings_of_level(4)<cr>" },
    ['<leader>ow'] = { "zR<cmd>lua require('helpers.markdown').fold_headings_of_level(5)<cr>" },
    -- ['<leader>oa'] = { "zR" },
    -- ['<leader>oo'] = { "zR" },

    ['<C-z>'] = { '<cmd>lua Snacks.zen.zen()<cr>' },

    ['<leader>lc'] = {
      "<cmd>lua vim.diagnostic.open_float()<cr><cmd>lua vim.diagnostic.open_float()<cr>wwy$<cmd>sleep 10ms<cr><cmd>:q<cr><cmd>lua require('user.helpers').search_chrome_yank()<cr>",
    },

    ['gd'] = { '<cmd>Lspsaga goto_definition<cr>' },
    ['gR'] = { '<cmd>Lspsaga finder<cr>' },
    ['<leader>lE'] = { '<cmd>Lspsaga diagnostic_jump_prev<cr>' },
    ['<leader>le'] = { '<cmd>Lspsaga diagnostic_jump_next<cr>' },
    ['<leader>lr'] = { '<cmd>Lspsaga rename<cr>' },
    ['<leader>lR'] = { '<cmd>LspRestart<cr>' },
    ['<leader>ll'] = { '<cmd>Lspsaga hover_doc<cr>' },
    ['<leader>lo'] = { '<cmd>Lspsaga outline<cr>' },
    ['<leader>ls'] = { '<cmd>Lspsaga outline<cr>' },
    ['<leader>ld'] = { '<cmd>Lspsaga show_line_diagnostics<cr>' },
    ['<leader>la'] = { '<cmd>Lspsaga code_action<cr>' },
    ['<leader>lD'] = { '<cmd>Lspsaga show_buf_diagnostics<cr>' },

    ['<A-e>'] = { '<cmd>w<cr>' },
    ['<leader>hr'] = { "<cmd>lua require('user/react-helpers').commands()<cr>" },
    ['<leader>hg'] = { "<cmd>lua require('user/git').commands()<cr>" },
    ['<leader>hj'] = { "<cmd>lua require('user/jira-helpers').commands()<cr>" },

    ['<leader>td'] = { '<cmd>TodoTrouble<cr>' },

    ['yb'] = { '<cmd>lua require("helpers.markdown").yank_code_block()<cr>' },

    ['<C-j>'] = { '<cmd>lua require("helpers.tmux").move_bottom()<cr>' },
    ['<C-h>'] = { '<cmd>lua require("helpers.tmux").move_top()<cr>' },

    ['<A-j>'] = { '<cmd>lua require("helpers.tmux").move_bottom()<cr>' },
    ['<A-h>'] = { '<cmd>lua require("helpers.tmux").move_left()<cr>' },
    ['<A-k>'] = { '<cmd>lua require("helpers.tmux").move_top()<cr>' },
    ['<A-l>'] = { '<cmd>lua require("helpers.tmux").move_right()<cr>' },

    ['<A-r>'] = { "<cmd>lua require('zen-mode').toggle({window= {width = 1}})<cr>" }, --FIX: This should just use the snacks version, but need to figure out the window. Also fights with other zen

    ['<A-s>'] = { ':vsp<cr>:sleep 50m<cr><C-o>' },
    ['<A-S>'] = { ':sp<cr>:sleep 50m<cr><C-o>' },
    ["'"] = { '$' },
    ['0'] = { '^' },
    ['t'] = { 'f' },
    -- ['T'] = { 't' },

    ['<leader>0'] = { 'f=w' },

    ['<leader>='] = { 'F=F=w' },
    ['caè'] = { 'ca{' },
    ['ciè'] = { 'ci{' },

    ['vaè'] = { 'va{' },
    ['viè'] = { 'vi{' },
    ['tè'] = { 'f{' },
    ['Tè'] = { '{' },
    ['vw'] = { 've' },
    ['vtè'] = { 'vt{' },
    ['vt8'] = { 'vt(' },
    ['<bs>'] = { 'b' },
    ['<esc>'] = { '0' },
    ['s'] = { '/' },
    ['Q'] = { '@' },

    ['<C-u>'] = { '<esc>', desc = 'Exit insert mode' },
    -- ['<leader><leader>'] = { '@' },
    ['X'] = { 's' },
    ['<leader>se'] = { '<cmd>lua require("luasnip.loaders").edit_snippet_files()<cr><cr>")' },
    ['<leader>ip'] = { '<cmd>IconPickerNormal<cr>' },

    --NOTE: old quit, in terminal i'm faking it ['<leader>q'] = { '<C-\\><C-n>:q<cr>' },
    --FIX: If more than one window open it should close the window if not do the terminal trick
    ['<leader>q'] = { '<cmd>write<cr><cmd>term<cr>' },
    ['<A-q>'] = { '<cmd>write<cr><cmd>term<cr>' },
    ['<M-w>'] = { '<cmd>q<cr>' },

    ['<leader>w'] = { '<cmd>only<cr><cmd>lua os.execute("tmux resize-pane -Z")<cr>' },

    ['H'] = { '^' },
    ['L'] = { '$' },

    ['ga'] = { '%', desc = '' },

    ['gA'] = { '%%', desc = '' },
    -- ['<C-g>'] = function()
    --   Snacks.picker.grep { layout = 'ivy_split', need_search = false, limit = 30, matcher = { fuzzy = false, sort_empty = false } }
    -- end,
  },

  tn = {
    ['<leader>x'] = function()
      local word = vim.fn.expand '<cWORD>'
      vim.notify('chmod +x ' .. word, vim.log.levels.INFO)
      vim.fn.chansend(vim.b.terminal_job_id, 'chmod +x ' .. word .. '\n')
      vim.cmd.startinsert()
    end,
    ['<M-b>'] = function()
      vim.fn.chansend(vim.b.terminal_job_id, 'make build' .. '\n')
      vim.cmd.startinsert()
    end,
    ['<cr>'] = function()
      require('helpers.term_path').handle_enter()
    end,
  },

  -- Terminal Mode
  t = {
    ['<M-o>'] = '<C-\\><C-n><C-o>',
    ['<M-i>'] = '<C-\\><C-n><C-i>',
    ['è'] = { 'p', desc = 'Print' },
    ['<M-b>'] = function()
      vim.fn.chansend(vim.b.terminal_job_id, 'make build' .. '\n')
      vim.cmd.startinsert()
    end,
    ['<M-y>'] = function()
      vim.fn.chansend(vim.b.terminal_job_id, 'make start' .. '\n')
      vim.cmd.startinsert()
    end,
    --TODO: Refactor me out as this is a duplicate of the below
    ['<C-p>'] = function()
      local tmpfile = '/tmp/nvim_term_cwd'
      vim.fn.chansend(vim.b.terminal_job_id, 'pwd > ' .. tmpfile .. ' && clear\n')
      vim.wait(80)

      local cwd = vim.fn.readfile(tmpfile)[1]
      if not cwd then
        print 'Failed to read terminal cwd.'; return
      end

      local picker_ui = require('fff.picker_ui')
      local orig_select = picker_ui.select
      local orig_close = picker_ui.close
      local term_win = vim.api.nvim_get_current_win()

      picker_ui.select = function(action)
        picker_ui.select = orig_select
        picker_ui.close = orig_close

        if not picker_ui.state.active then return orig_select(action) end
        local items = picker_ui.state.filtered_items
        if #items == 0 or picker_ui.state.cursor > #items then return orig_select(action) end
        local item = items[picker_ui.state.cursor]
        if not item then return orig_select(action) end

        action = action or 'edit'
        if action ~= 'edit' then return orig_select(action) end

        local abs_path = vim.fs.normalize(cwd .. '/' .. item.relative_path)
        if not abs_path then return orig_select(action) end

        vim.cmd('stopinsert')
        picker_ui.close()

        if _G.NVIM_TERMINAL_ONLY then
          -- Terminal-only: replace tmux pane with a fresh nvim instance
          os.execute('tmux respawn-pane -k -c ' .. vim.fn.shellescape(cwd) .. ' nvim ' .. vim.fn.shellescape(abs_path))
        else
          -- Full nvim: replace the terminal buffer in its own window
          pcall(vim.api.nvim_set_current_win, term_win)
          vim.cmd('e! ' .. vim.fn.fnameescape(abs_path))
        end
      end

      picker_ui.close = function(...)
        picker_ui.select = orig_select
        picker_ui.close = orig_close
        return orig_close(...)
      end
      -- Force-load nvim-treesitter so fff's preview gets treesitter highlighting
      -- (in terminal-only mode no file has been opened yet, so lazy loading on
      -- BufReadPost/BufNewFile hasn't fired)
      pcall(require, 'nvim-treesitter')

      require('fff').find_files { cwd = cwd }

      -- Ensure insert mode in fff's input prompt
      vim.schedule(function()
        pcall(vim.cmd, 'startinsert!')
      end)
    end,
    ['<C-g>'] = function()
      local tmpfile = '/tmp/nvim_term_cwd'
      vim.fn.chansend(vim.b.terminal_job_id, 'pwd > ' .. tmpfile .. ' && clear\n')
      vim.wait(80)

      local cwd = vim.fn.readfile(tmpfile)[1]
      if not cwd then
        print 'Failed to read terminal cwd.'; return
      end

      local term_win = vim.api.nvim_get_current_win()
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')

      require('telescope.builtin').live_grep {
        cwd = cwd,
        winblend = 0,
        preview = false,
        sorting_strategy = 'ascending',
        layout_strategy = 'vertical',
        layout_config = {
          vertical = { mirror = false },
          width = 1200,
          height = 1200,
          preview_cutoff = 1,
        },
        border = true,
        attach_mappings = function(_, map)
          map('i', '<CR>', function()
            local selection = action_state.get_selected_entry()
            if not selection then return end

            local abs_path = selection.filename or selection[1]
            if not abs_path then return end
            abs_path = vim.fn.fnamemodify(abs_path, ':p')

            local line = selection.lnum
            local col = selection.col

            actions.close(vim.api.nvim_get_current_buf())

            if _G.NVIM_TERMINAL_ONLY then
              local cmd = 'tmux respawn-pane -k -c ' .. vim.fn.shellescape(cwd) .. ' nvim '
              if line then cmd = cmd .. ' +' .. line end
              os.execute(cmd .. vim.fn.shellescape(abs_path))
            else
              pcall(vim.api.nvim_set_current_win, term_win)
              vim.cmd('e! ' .. vim.fn.fnameescape(abs_path))
              if line then
                vim.api.nvim_win_set_cursor(term_win, { line, (col or 1) - 1 })
                vim.cmd('normal! zz')
              end
            end
          end)
          return true
        end,
      }
    end,
    ['<C-^M>'] = { '<NL>', desc = 'New Line' },
    ['<A-q>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<C-q>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<C-t>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },

    ['<M-w>'] = { '<C-\\><C-n><cmd>q<cr>', desc = 'Quit' },

    ['<C-h>'] = { '<Cmd>wincmd h<cr><C-\\><C-n>i', desc = 'Move to Left Window' },
    ['<Esc>'] = { '<C-\\><C-N>', desc = 'Go to normal mode' },
    ['kj'] = { '<C-\\><C-N>', desc = 'Go to normal mode' },
    ['<C-u>'] = { '<C-\\><C-n><cmd>lua vim.defer_fn(function() vim.api.nvim_input("<leader>") end, 150)<CR>', desc = 'Exit terminal mode, wait, and trigger leader' },

    ['<A-s>'] = { '<cmd>lua os.execute("tmux split-window -h")<cr>' },
    ['<A-S>'] = { '<cmd>lua os.execute("tmux split-window -v")<cr>' },

    -- ['<C-f>'] = { '<C-\\><C-N><cmd>lua GlobalSnacksPicker()<cr>' },
    ['<C-f>'] = { '<C-\\><C-N>/' },

    ['<A-j>'] = { '<cmd>lua require("helpers.tmux").move_bottom()<cr>' },
    ['<A-h>'] = { '<cmd>lua require("tmux").move_left()<cr>' },
    ['<A-k>'] = { '<cmd>lua require("tmux").move_top()<cr>' },
    ['<A-l>'] = { '<cmd>lua require("tmux").move_right()<cr>' },

    ['<C-k>'] = { '<Cmd>wincmd k<cr>', desc = 'Move to Upper Window' },
    ['<C-l>'] = { '<Cmd>wincmd l<cr><C-\\><C-n>i', desc = 'Move to Right Window' },
  },

  -- Visual Mode
  v = {
    ['<leader>jq'] = { '<cmd>JqVisual<CR>', desc = 'Shift right' },
    -- ['<leader>jv'] = { '<cmd>JiraView<cr>', desc = 'View jira issue' },

    ['e'] = { 'E' },
    ['<leader>re'] = { '<cmd>lua require("react-extract").extract_to_current_file()<cr>' },
    ['<leader>rE'] = { '<cmd>lua require("react-extract").extract_to_new_file()<cr>' },

    ['H'] = { '^' },
    ['L'] = { '$' },

    ['|'] = { '1', desc = 'Pipe' },
    ['?'] = { '2', desc = 'Question mark' },
    ['&'] = { '3', desc = 'Ampersand' },
    ['/'] = { '4', desc = 'Forward slash' },
    ['='] = { '6', desc = 'Equal sign' },
    ['['] = { '7', desc = 'Opening square bracket' },
    [']'] = { '8', desc = 'Closing square bracket' },
    ['@'] = { '9', desc = 'At symbol' },
    ['à'] = { '0', desc = 'Number zero with accent' },
    ['<leader>qt'] = { ':!quicktype --just-types -l typescript<CR>', desc = 'Run quicktype for TypeScript' },

    -- NOTE: [ Ai ]
    ['<leader>ai'] = { 'y<cmd>GpChatNew vsplit<CR>Gp' },

    ['<leader>ao'] = { ':GpOrganize<CR>', desc = 'Organize code' },
    ['<leader>aO'] = { ':GpOptimize<CR>', desc = 'Optimize code' },
    ['<leader>ac'] = { ':GpComplete<CR>', desc = 'Complete code' },
    ['<leader>as'] = { ':GpSummarize<CR>', desc = 'Summarize code' },
    ['<leader>af'] = { ':GpFixBugs<CR>', desc = 'Fix bugs' },
    ['<leader>ae'] = { ':GpExplain<CR>', desc = 'Explain code' },
    ['<leader>ar'] = { ':GpReadability<CR>', desc = 'Analyze code readability' },
    ['<leader>ax'] = { ':GpConvert<CR>', desc = 'Convert selection (prompts for target)' },
    ['<leader>a.'] = { ':GpCustomCmd<CR>', desc = 'Execute custom command on selection' },

    ['<leader>c'] = { "<esc><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<cr>", desc = 'Toggle comment' },

    ['è'] = { 'p', desc = '' },
    ['<'] = { '<gv', desc = '' },
    ['>'] = { '>gv', desc = '' },
    ['ga'] = { '%', desc = '' },
    ['gA'] = { '%%', desc = '' },
    ['y'] = { 'myy`y', desc = '' },
    ['Y'] = { 'myY`y', desc = '' },
    ["'"] = { "xi''<esc>hp", desc = '' },
  },

  -- Insert Mode
  i = {
    ['<C-f>'] = { '$', desc = 'Move to end of line' },
    ['<C-o>'] = { '<esc><C-o>', desc = 'Exit insert mode and execute one <C-o>' },
    ['<C-i>'] = { '<esc><C-i>', desc = 'Exit insert mode and execute one <C-i>' },
    ['<A-o>'] = { '<esc><C-o>', desc = 'Exit insert mode and execute one <C-o>' },
    ['<A-i>'] = { '<esc><C-i>', desc = 'Exit insert mode and execute one <C-i' },

    ['<c-j>'] = { "<cmd>lua require'luasnip'.jump(1)<cr>", desc = 'Jump to next snippet' },
    ['<c-k>'] = { "<cmd>lua require'luasnip'.jump(-1)<cr>", desc = 'Jump to previous snippet' },

    ['è'] = { 'p', desc = 'Paste after cursor' },
    ['ò'] = { '#', desc = 'Comment line' },
    ['jj'] = { '<esc>', desc = 'Exit insert mode' },
    ['JJ'] = { '<esc>', desc = 'Exit insert mode' },
    ['kj'] = { '<esc>', desc = 'Exit insert mode' },
    ['<C-u>'] = { '<esc>', desc = 'Exit insert mode' },
    ['KJ'] = { '<esc>', desc = 'Exit insert mode' },
    ['jJ'] = { '<esc><cmd>w!<cr>', desc = 'Save and exit insert mode' },
    ['jp'] = { '<esc>:q!<cr>', desc = 'Quit without saving' },
    ['jk'] = { '<esc>A', desc = 'Append at end of line' },
    ['jK'] = { '<esc>A<space>', desc = 'Append at end of line with space' },
    ['jè'] = { '<esc>A{<enter><esc>ddO', desc = 'Append curly braces on new line' },
    -- ['ji'] = { '<esc>I<space>', desc = 'Insert at beginning of line with space' },
    ['jI'] = { '<esc>I', desc = 'Insert at beginning of line' },
    ['<C-s>'] = { '<cmd>w<cr><esc>', desc = 'Save file' },
    ['<C-S>'] = { '<cmd>noa w<cr><esc>', desc = 'Save file without autocommands' },

    ['jo'] = { '<esc>o', desc = 'Open new line below' },
    ['jO'] = { '<esc>ko', desc = 'Open new line above' },

    ['jy'] = { '<esc>yy<esc>p', desc = 'Yank line and paste' },
    ['jd'] = { '<esc>dd', desc = 'Delete line' },
    ['jl'] = { '<esc>la', desc = 'Append at end of line' },
    ['jf'] = { '<esc>A<space>from<space>', desc = 'Append "from" at end of line' },
    ['j0'] = { '<esc>A<space>=<space>', desc = 'Append "= " at end of line' },
    ['§'] = { '`', desc = 'Jump to mark' },
    [';;'] = { '<esc>A;<esc>', desc = 'Append semicolon at end of line' },

    ['<C-Del>'] = { '<C-w>', desc = 'Delete word' },
    ['<C-BS>'] = { '<C-w>', desc = 'Delete word' },

    ['<C-w>'] = { '<cmd>q<cr>' },
    ['<M-w>'] = { '<cmd>q<cr>' },
    ['<C-e>'] = { '<cmd>Oil<cr>', desc = 'Oil from insert mode' },
  },

  -- Command mode
  c = {
    ['<C-Del>'] = { '<C-w>', desc = 'Delete word' },
  },
}
