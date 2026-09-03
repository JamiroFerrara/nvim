local util = require 'helpers.util'

return {
  -- Normal Mode
  n = {
    -- Dev
    ['<leader>np'] = { '<cmd>Neopostman<CR>', desc = 'Neopostman' },
    ['<leader>nc'] = { '<cmd>ChromeNetwork<CR>', desc = 'Chrome Network' },
    ['<leader>cn'] = { '<cmd>ChromeNetwork<cr>', desc = 'Chrome Network' },
    ['<leader>lp'] = { '<cmd>Lazy profile<CR>', desc = 'Lazy profile' },
    ['<leader>ji'] = { '<cmd>Neojira<cr>', desc = 'Neojira' },
    ['<leader>jq'] = { '<cmd>JqFile<CR>', desc = 'JqFile' },
    ['<C-r>'] = { "<cmd>silent !tmux split-window -v -p 50 'source ~/.zshrc && run_script'<CR>", desc = 'Open split, source .zshrc, and run the script' },

    -- Editor
    ['<leader>fb'] = {
      function()
        pcall(vim.api.nvim_command, 'doautocmd User event_conform')
        require('conform').format { async = true, lsp_fallback = true }
      end,
      desc = 'Format buffer',
    },
    ['<leader>ii'] = {
      function()
        pcall(vim.api.nvim_command, 'doautocmd User event_toggler')
        require('nvim-toggler').toggle()
      end,
      desc = 'Toggle inline (nvim-toggler)',
    },
    ['<leader>ss'] = { '<cmd>luafile $MYVIMRC<CR>', desc = 'Source config' },
    ['<leader>c'] = { '<cmd>lua require("Comment.api").toggle.linewise.current()<cr>', desc = 'Toggle comment' },
    ['cc'] = { '<cmd>lua require("Comment.api").toggle.linewise.current()<cr>', desc = 'Toggle comment' },
    ['<leader>tt'] = { '<cmd>TransparentToggle<cr>', desc = 'Toggle transparency' },
    ['<leader>tw'] = {
      function()
        vim.opt.wrap = not vim.opt.wrap:get()
        vim.notify('Wrap ' .. (vim.opt.wrap:get() and 'on' or 'off'), vim.log.levels.INFO)
      end,
      desc = 'Toggle line wrap',
    },
    ['<C-z>'] = { '<cmd>lua Snacks.zen.zen()<cr>', desc = 'Zen mode' },
    ['<A-r>'] = { "<cmd>lua require('zen-mode').toggle({window= {width = 1}})<cr>", desc = 'Zen mode (full width)' }, --FIX: This should just use the snacks version, but need to figure out the window. Also fights with other zen

    -- Files & Buffers
    ['<leader>e'] = { '<cmd>Neotree<cr>', desc = 'Toggle Neotree' },
    -- ['<C-e>'] = { '<cmd>lua require("snacks").explorer()<cr>', desc = 'Toggle Neotree' },
    ['<leader>lg'] = { '<cmd>lua os.execute("tmux neww lazygit")<cr>', desc = 'Open lazygit in a new tmux window' },
    ['<leader>dB'] = { '<cmd>DBUI<cr>', desc = 'Open DBUI' },
    ['<leader>b'] = { ':b ', desc = 'List buffers' },
    ['mt'] = { '<cmd>e TODO.md<cr>', desc = 'Open TODO.md' },
    ['cp'] = { "<cmd>let @+ = expand('%:p')<cr>", desc = 'Copy current file path' },
    ['<leader>se'] = { '<cmd>lua require("luasnip.loaders").edit_snippet_files()<cr><cr>")', desc = 'Edit snippet files' },
    ['<leader>ip'] = { '<cmd>IconPickerNormal<cr>', desc = 'Icon picker' },
    ['<leader>w'] = { '<cmd>only<cr><cmd>lua os.execute("tmux resize-pane -Z")<cr>', desc = 'Close other windows' },
    ['<A-e>'] = { '<cmd>w<cr>', desc = 'Write (save)' },
    --NOTE: old quit, in terminal i'm faking it ['<leader>q'] = { '<C-\\><C-n>:q<cr>' },
    --FIX: If more than one window open it should close the window if not do the terminal trick
    ['<leader>q'] = { '<cmd>write<cr><cmd>term<cr>', desc = 'Write and open terminal' },
    ['<A-q>'] = { '<cmd>write<cr><cmd>term<cr>', desc = 'Write and open terminal' },
    ['<M-w>'] = { '<cmd>q<cr>', desc = 'Close window' },

    -- Search
    ['<leader>sf'] = { ':%s/\\\\n/\\r/g', desc = 'Search and replace newlines' },
    ['<leader>fw'] = { "<cmd>lua require'telescope.builtin'.live_grep(GET_IVY())<cr>", desc = 'Live grep (ivy)' },
    ['<C-g>'] = { "<cmd>lua require'telescope.builtin'.live_grep(GET_IVY())<cr>", desc = 'Live grep (ivy)' },
    ['<leader>lc'] = {
      "<cmd>lua vim.diagnostic.open_float()<cr><cmd>lua vim.diagnostic.open_float()<cr>wwy$<cmd>sleep 10ms<cr><cmd>:q<cr><cmd>lua require('user.helpers').search_chrome_yank()<cr>",
      desc = 'Search Chrome for symbol under cursor',
    },
    -- ['<C-g>'] = function()
    --   Snacks.picker.grep { layout = 'ivy_split', need_search = false, limit = 30, matcher = { fuzzy = false, sort_empty = false } }
    -- end,

    -- Git
    ['<leader>gj'] = { '<cmd>lua require("gitsigns").next_hunk()<cr>', desc = 'Next hunk' },
    ['<leader>gk'] = { '<cmd>lua require("gitsigns").prev_hunk()<cr>', desc = 'Prev hunk' },
    ['gj'] = { '<cmd>lua require("gitsigns").nav_hunk("next", { navigation_message = false })<cr>', desc = 'Next hunk' },
    ['gk'] = { '<cmd>lua require("gitsigns").nav_hunk("prev", { navigation_message = false })<cr>', desc = 'Prev hunk' },
    ['<leader>gp'] = { '<cmd>lua require("gitsigns").preview_hunk()<cr>', desc = 'Preview hunk' },
    ['<leader>gh'] = { '<cmd>lua require("gitsigns").reset_hunk()<cr>', desc = 'Reset hunk' },
    ['gh'] = { '<cmd>lua require("gitsigns").reset_hunk()<cr>', desc = 'Reset hunk' },
    ['<leader>gr'] = { '<cmd>lua require("gitsigns").reset_buffer()<cr>', desc = 'Reset buffer' },
    ['<leader>gs'] = { '<cmd>lua require("gitsigns").stage_hunk()<cr>', desc = 'Stage hunk' },
    ['<leader>gu'] = { '<cmd>lua require("gitsigns").undo_stage_hunk()<cr>', desc = 'Undo stage hunk' },
    ['<leader>gd'] = { '<cmd>lua require("gitsigns").diffthis()<cr>', desc = 'Diff this (gitsigns)' },

    -- LSP
    ['gd'] = { '<cmd>Lspsaga goto_definition<cr>', desc = 'Go to definition' },
    ['gR'] = { '<cmd>Lspsaga finder<cr>', desc = 'References (finder)' },
    ['<leader>lE'] = { '<cmd>Lspsaga diagnostic_jump_prev<cr>', desc = 'Prev diagnostic' },
    ['<leader>le'] = { '<cmd>Lspsaga diagnostic_jump_next<cr>', desc = 'Next diagnostic' },
    ['<leader>lr'] = { '<cmd>Lspsaga rename<cr>', desc = 'Rename symbol' },
    ['<leader>lR'] = { '<cmd>LspRestart<cr>', desc = 'Restart LSP' },
    ['<leader>ll'] = { '<cmd>Lspsaga hover_doc<cr>', desc = 'Hover doc' },
    ['<leader>lo'] = { '<cmd>Lspsaga outline<cr>', desc = 'Outline' },
    ['<leader>ls'] = { '<cmd>Lspsaga outline<cr>', desc = 'Outline' },
    ['<leader>ld'] = { '<cmd>Lspsaga show_line_diagnostics<cr>', desc = 'Line diagnostics' },
    ['<leader>la'] = { '<cmd>Lspsaga code_action<cr>', desc = 'Code action' },
    ['<leader>lD'] = { '<cmd>Lspsaga show_buf_diagnostics<cr>', desc = 'Buffer diagnostics' },

    -- Harpoon
    ['<leader>m'] = { '<cmd>lua require("harpoon.mark").add_file()<cr>', desc = 'Harpoon: add file' },
    ['<leader>M'] = { '<cmd>lua require("harpoon.ui").toggle_quick_menu()<cr>', desc = 'Harpoon: quick menu' },
    ['<leader>1'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>', desc = 'Harpoon: file 1' },
    ['<leader>2'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>', desc = 'Harpoon: file 2' },
    ['<leader>3'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>', desc = 'Harpoon: file 3' },
    ['<leader>4'] = { '<cmd>lua require("harpoon.ui").nav_file(4)<cr>', desc = 'Harpoon: file 4' },
    ['<leader>5'] = { '<cmd>lua require("harpoon.ui").nav_file(5)<cr>', desc = 'Harpoon: file 5' },
    ['<leader>6'] = { '<cmd>lua require("harpoon.ui").nav_file(6)<cr>', desc = 'Harpoon: file 6' },
    ['<leader>7'] = { '<cmd>lua require("harpoon.ui").nav_file(7)<cr>', desc = 'Harpoon: file 7' },
    ['{'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>', desc = 'Harpoon: file 1' },
    ['}'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>', desc = 'Harpoon: file 2' },
    ['+'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>', desc = 'Harpoon: file 3' },

    -- AI
    ['<leader>ai'] = { '<cmd>Opencode<CR>', desc = 'Opencode' },
    ['<leader>aa'] = { '<cmd>GpChatNew vsplit<CR>', desc = 'GpChat new (vsplit)' },
    ['<leader>av'] = { '<cmd>lua require("user.helpers").visualModeAi()<CR>', desc = 'AI visual mode' },
    ['<leader>am'] = { '<cmd>lua require("user.helpers").apiMockAi()<CR>', desc = 'AI mock API' },
    ['<leader>at'] = { '<cmd>lua require("user.helpers").cs2ts()<CR>', desc = 'C# to TypeScript' },
    ['<leader>ac'] = { '<cmd>Copilot<CR>', desc = 'Copilot complete' },
    ['<leader>hr'] = { "<cmd>lua require('user/react-helpers').commands()<cr>", desc = 'React helpers' },
    ['<leader>hg'] = { "<cmd>lua require('user/git').commands()<cr>", desc = 'Git helpers' },
    ['<leader>hj'] = { "<cmd>lua require('user/jira-helpers').commands()<cr>", desc = 'Jira helpers' },

    -- Org
    ['<leader>ot'] = { '<cmd>lua require("helpers.org-menu"):_open_todo_client_submenu()<cr>', desc = 'Browse project TODOs' },
    ['<leader>oa'] = { '<cmd>lua require("helpers.org-menu"):open_custom_menu()<cr>', desc = 'Agenda menu' },
    ['<leader>oT'] = { '<cmd>lua require("helpers.org-capture").open_all_todos()<cr>', desc = 'All project TODOs' },
    ['<leader>oc'] = { '<cmd>lua require("helpers.org-menu"):open_capture_client_submenu()<cr>', desc = 'Capture project TODO' },
    ['<leader>ocd'] = { "<cmd>lua require('helpers.org-capture').capture_with_picker('d')<cr>", desc = 'Capture DTM TODO' },
    ['<leader>oca'] = { "<cmd>lua require('helpers.org-capture').capture_with_picker('a')<cr>", desc = 'Capture Allitude TODO' },
    ['<leader>oci'] = { "<cmd>lua require('helpers.org-capture').capture_with_picker('i')<cr>", desc = 'Capture ING TODO' },
    ['<leader>oct'] = { "<cmd>lua require('helpers.org-capture').capture_with_picker('t')<cr>", desc = 'Capture Italfinance TODO' },
    --TODO: Obsidian Commands
    --Theese are the obsidian related commands, but with org mode now need to
    --figure out what to actually do with them.
    -- ['<leader>ob'] = { '<cmd>ObsidianBacklinks<cr>' },
    -- ['<leader>ot'] = { '<cmd>ObsidianToday<cr>' },
    -- ['<leader>oT'] = { '<cmd>ObsidianTomorrow<cr>' },
    -- ['<leader>oy'] = { '<cmd>ObsidianYesterday<cr>' },
    -- ['<leader>oa'] = { "zR" },
    -- ['<leader>oo'] = { "zR" },

    -- Make / Run
    ['<leader>mp'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make publish; tmux select-pane -U")<CR>', desc = 'Make publish' },
    ['<leader>md'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make down; tmux select-pane -U")<CR>', desc = 'Make down' },
    ['<leader>mr'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make run; tmux select-pane -U")<CR>', desc = 'Make run' },
    ['<leader>mb'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make build; tmux select-pane -U")<CR>', desc = 'Make build' },
    ['<leader>mt'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make test; tmux select-pane -U")<CR>', desc = 'Make test' },
    ['<leader>ml'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make local; tmux select-pane -U")<CR>', desc = 'Make local' },
    ['<leader>ms'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make start; tmux select-pane -U")<CR>', desc = 'Make start' },
    ['<leader>mw'] = {
      '<cmd>lua os.execute("tmux split-window -v -p 20 make watch; tmux select-pane -U")<CR><cmd>DapContinue<cr>',
      desc = 'Make watch and continue',
    },
    ['<A-b>'] = {
      function()
        require('helpers.make_term').run_or_focus('build', 'clear && make build')
      end,
      desc = 'Make build',
    },
    ['<C-y>'] = {
      function()
        require('helpers.make_term').run_or_focus('start', 'clear && make start')
      end,
      desc = 'Make start',
    },
    ['<A-y>'] = {
      function()
        require('helpers.make_term').run_or_focus('make', 'clear && source $HOME/.functions && m')
      end,
      desc = 'Make (m)',
    },
    ['<leader>x'] = { '<cmd>.!sh<CR>', desc = 'Execute line under cursor' },

    -- Terminal & Tmux
    ['<leader>th'] = {
      '<cmd>lua os.execute("tmux if-shell \\"[ $(tmux list-panes | wc -l) -eq 1 ]\\" \\"split-window -v -l 10\\" \\"resize-pane -Z\\"")<CR>',
      desc = 'Toggle term bottom',
    },
    ['<A-t>'] = { '<cmd>term<cr>', desc = 'Open terminal' },
    ['<C-t>'] = {
      '<cmd>lua os.execute("tmux if-shell \\"[ $(tmux list-panes | wc -l) -eq 1 ]\\" \\"split-window -v -l 10\\" \\"resize-pane -Z; select-pane -D\\"")<CR>',
      desc = 'Toggle term bottom',
    },
    -- ['<A-m>'] = {
    --   '<cmd>lua os.execute("tmux if-shell \\"[ $(tmux list-panes | wc -l) -eq 1 ]\\" \\"split-window -v -l 10\\" \\"resize-pane -Z; select-pane -D\\" && tmux send-keys \'m\' Enter")<CR>',
    --   desc = 'toggle term bottom and run m',
    -- },
    ['<leader>ap'] = { '<cmd>lua os.execute("/home/jferrara/.scripts/v-script.sh")<CR>', desc = 'Run v-script' },
    ['<C-j>'] = { '<cmd>lua require("helpers.tmux").move_bottom()<cr>', desc = 'Move to bottom pane (tmux)' },
    ['<C-h>'] = { '<cmd>lua require("helpers.tmux").move_top()<cr>', desc = 'Move to top pane (tmux)' },
    ['<A-j>'] = { '<cmd>lua require("helpers.tmux").move_bottom()<cr>', desc = 'Move to bottom pane (tmux)' },
    ['<A-h>'] = { '<cmd>lua require("helpers.tmux").move_left()<cr>', desc = 'Move to left pane (tmux)' },
    ['<A-k>'] = { '<cmd>lua require("helpers.tmux").move_top()<cr>', desc = 'Move to top pane (tmux)' },
    ['<A-l>'] = { '<cmd>lua require("helpers.tmux").move_right()<cr>', desc = 'Move to right pane (tmux)' },
    ['<A-s>'] = { ':vsp<cr>:sleep 50m<cr><C-o>', desc = 'Vertical split' },
    ['<A-S>'] = { ':sp<cr>:sleep 50m<cr><C-o>', desc = 'Horizontal split' },

    -- Movement
    ['H'] = { '^', desc = 'Start of line' },
    ['L'] = { '$', desc = 'End of line' },
    ['0'] = { '^', desc = 'Start of line' },
    ["'"] = { '$', desc = 'End of line' },
    ['à'] = { '0', desc = 'Start of line' },
    ['e'] = { 'E', desc = 'End of word' },
    ['t'] = { 'f', desc = 'Find char' },
    -- ['T'] = { 't' },
    ['s'] = { '/', desc = 'Search' },
    ['f'] = { '/', desc = 'Search' },
    ['F'] = { "<cmd>lua require('flash').jump()<cr>", desc = 'Flash jump' },
    ['<bs>'] = { 'b', desc = 'Back a word' },
    ['<esc>'] = { '0', desc = 'Start of line' },
    ['J'] = { '<C-d>', desc = 'Scroll down' },
    ['K'] = { '<C-u>', desc = 'Scroll up' },
    ['N'] = { 'Nzzzv', desc = 'Prev search result' },
    ['n'] = { 'nzzzv', desc = 'Next search result' },
    ['U'] = { ':redo<cr>', desc = 'Redo' },
    ['Y'] = { 'y$', desc = 'Yank to end of line' },
    ['X'] = { 's', desc = 'Substitute char' },
    ['ga'] = { '%', desc = 'Jump to matching bracket' },
    ['gA'] = { '%%', desc = 'Jump to matching bracket' },
    ['Q'] = { '@', desc = 'Replay macro' },
    ['<A-o>'] = { '<C-o>', desc = 'Jump back' },
    ['<A-i>'] = { '<C-i>', desc = 'Jump forward' },
    -- ['<C-o>'] = { '<C-o>', desc = '' },
    ['<C-o>'] = { '<cmd>bprev<cr>', desc = 'Previous buffer' },
    ['<C-i>'] = { '<C-i>', desc = 'Jump forward' },
    ['<A-n>'] = { '*', desc = 'Search word under cursor' },
    ['<leader>0'] = { 'f=w', desc = 'Find = then word' },
    ['<leader>='] = { 'F=F=w', desc = 'Find = backward' },
    ['<leader>j'] = { '}', desc = 'Next paragraph' },
    ['<leader>k'] = { '{', desc = 'Prev paragraph' },
    ['ç'] = { 'J', desc = 'Join lines' },
    ['|'] = { '1', desc = 'Digit 1' },
    ['?'] = { '2', desc = 'Digit 2' },
    ['&'] = { '3', desc = 'Digit 3' },
    ['/'] = { '4', desc = 'Digit 4' },

    -- Marks
    ['m'] = { "'", desc = 'Go to mark' },

    -- Indentation
    ['>'] = { '>>', desc = 'Shift right' },
    ['<'] = { '<<', desc = 'Shift left' },

    -- Text Objects
    ['ciu'] = { 'ci{', desc = 'Change inside braces' },
    ['diu'] = { 'di{', desc = 'Delete inside braces' },
    ['viu'] = { 'vi{', desc = 'Select inside braces' },
    ['cau'] = { 'ca{', desc = 'Change around braces' },
    ['dau'] = { 'da{', desc = 'Delete around braces' },
    ['vau'] = { 'va{', desc = 'Select around braces' },
    ['ci2'] = { 'ci"', desc = 'Change inside double quotes' },
    ['di2'] = { 'ci"', desc = 'Delete inside double quotes' },
    ['vi2'] = { 'vi"', desc = 'Select inside double quotes' },
    ['ca2'] = { 'ca"', desc = 'Change around double quotes' },
    ['da2'] = { 'ca"', desc = 'Delete around double quotes' },
    ['va2'] = { 'va"', desc = 'Select around double quotes' },
    ['cij'] = { 'ci[', desc = 'Change inside brackets' },
    ['dij'] = { 'di[', desc = 'Delete inside brackets' },
    ['vij'] = { 'vi[', desc = 'Select inside brackets' },
    ['caj'] = { 'ca[', desc = 'Change around brackets' },
    ['daj'] = { 'da[', desc = 'Delete around brackets' },
    ['vaj'] = { 'va[', desc = 'Select around brackets' },
    ['ci8'] = { 'ci(', desc = 'Change inside parens' },
    ['di8'] = { 'di(', desc = 'Delete inside parens' },
    ['vi8'] = { 'vi(', desc = 'Select inside parens' },
    ['ca8'] = { 'ca(', desc = 'Change around parens' },
    ['da8'] = { 'da(', desc = 'Delete around parens' },
    ['va8'] = { 'va(', desc = 'Select around parens' },
    ['caè'] = { 'ca{', desc = 'Change around braces' },
    ['ciè'] = { 'ci{', desc = 'Change inside braces' },
    ['vaè'] = { 'va{', desc = 'Select around braces' },
    ['viè'] = { 'vi{', desc = 'Select inside braces' },
    ['tè'] = { 'f{', desc = 'Find brace' },
    ['Tè'] = { '{', desc = 'Find brace backward' },
    ['vw'] = { 've', desc = 'Select word' },
    ['vtè'] = { 'vt{', desc = 'Select until brace' },
    ['vt8'] = { 'vt(', desc = 'Select until paren' },
    ['vap'] = { 'vip', desc = 'Select around paragraph' },

    -- Markdown & Folding
    ['<leader>or'] = { "zR<cmd>lua require('helpers.markdown').fold_headings_of_level(3)<cr>", desc = 'Fold headings level 3' },
    ['<leader>oe'] = { "zR<cmd>lua require('helpers.markdown').fold_headings_of_level(4)<cr>", desc = 'Fold headings level 4' },
    ['<leader>ow'] = { "zR<cmd>lua require('helpers.markdown').fold_headings_of_level(5)<cr>", desc = 'Fold headings level 5' },
    ['yb'] = { '<cmd>lua require("helpers.markdown").yank_code_block()<cr>', desc = 'Yank code block' },

    -- Misc
    ['<leader>fml'] = { '<cmd>CellularAutomaton make_it_rain<CR>', desc = 'Make it rain' },
    ['<leader>yy'] = { 'GVggy<cmd>q!<CR>', desc = 'Yank all and quit' },
    ['<leader>td'] = { '<cmd>TodoTrouble<cr>', desc = 'Todo (Trouble)' },
    ['<C-u>'] = { '<esc>', desc = 'Exit insert mode' },
    -- ['<leader><leader>'] = { '@' },
  },

  -- Visual Mode
  v = {
    -- AI
    ['<leader>ai'] = { 'y<cmd>GpChatNew vsplit<CR>Gp', desc = 'Send selection to GpChat' },
    ['<leader>ao'] = { ':GpOrganize<CR>', desc = 'Organize code' },
    ['<leader>aO'] = { ':GpOptimize<CR>', desc = 'Optimize code' },
    ['<leader>ac'] = { ':GpComplete<CR>', desc = 'Complete code' },
    ['<leader>as'] = { ':GpSummarize<CR>', desc = 'Summarize code' },
    ['<leader>af'] = { ':GpFixBugs<CR>', desc = 'Fix bugs' },
    ['<leader>ae'] = { ':GpExplain<CR>', desc = 'Explain code' },
    ['<leader>ar'] = { ':GpReadability<CR>', desc = 'Analyze code readability' },
    ['<leader>ax'] = { ':GpConvert<CR>', desc = 'Convert selection (prompts for target)' },
    ['<leader>a.'] = { ':GpCustomCmd<CR>', desc = 'Execute custom command on selection' },

    -- Search
    ['<leader>sl'] = {
      function()
        util.brave_search(util.visual_selection())
      end,
      desc = 'Search web (Brave, lucky)',
    },

    -- React
    ['<leader>re'] = { '<cmd>lua require("react-extract").extract_to_current_file()<cr>', desc = 'Extract to current file' },
    ['<leader>rE'] = { '<cmd>lua require("react-extract").extract_to_new_file()<cr>', desc = 'Extract to new file' },

    -- Jq / Quicktype
    ['<leader>jq'] = { '<cmd>JqVisual<CR>', desc = 'JqVisual' },
    -- ['<leader>jv'] = { '<cmd>JiraView<cr>', desc = 'View jira issue' },
    ['<leader>qt'] = { ':!quicktype --just-types -l typescript<CR>', desc = 'Run quicktype for TypeScript' },

    -- Edit
    ['<leader>c'] = { "<esc><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<cr>", desc = 'Toggle comment' },
    ['<'] = { '<gv', desc = 'Shift left' },
    ['>'] = { '>gv', desc = 'Shift right' },
    ['y'] = { 'myy`y', desc = 'Yank (keep cursor)' },
    ['Y'] = { 'myY`y', desc = 'Yank line (keep cursor)' },
    ["'"] = { "xi''<esc>hp", desc = 'Wrap in single quotes' },
    ['è'] = { 'p', desc = 'Paste' },
    ['e'] = { 'E', desc = 'End of word' },

    -- Movement
    ['H'] = { '^', desc = 'Start of line' },
    ['L'] = { '$', desc = 'End of line' },
    ['ga'] = { '%', desc = 'Jump to matching bracket' },
    ['gA'] = { '%%', desc = 'Jump to matching bracket' },

    -- Number marks
    ['|'] = { '1', desc = 'Pipe' },
    ['?'] = { '2', desc = 'Question mark' },
    ['&'] = { '3', desc = 'Ampersand' },
    ['/'] = { '4', desc = 'Forward slash' },
    ['='] = { '6', desc = 'Equal sign' },
    ['['] = { '7', desc = 'Opening square bracket' },
    [']'] = { '8', desc = 'Closing square bracket' },
    ['@'] = { '9', desc = 'At symbol' },
    ['à'] = { '0', desc = 'Number zero with accent' },
  },

  -- Insert Mode
  i = {
    -- Navigation
    ['<C-f>'] = { '$', desc = 'Move to end of line' },
    ['<C-o>'] = { '<esc><C-o>', desc = 'Exit insert mode and execute one <C-o>' },
    ['<C-i>'] = { '<esc><C-i>', desc = 'Exit insert mode and execute one <C-i>' },
    ['<A-o>'] = { '<esc><C-o>', desc = 'Exit insert mode and execute one <C-o>' },
    ['<A-i>'] = { '<esc><C-i>', desc = 'Exit insert mode and execute one <C-i>' },
    ['jk'] = { '<esc>A', desc = 'Append at end of line' },
    ['jK'] = { '<esc>A<space>', desc = 'Append at end of line with space' },
    ['jè'] = { '<esc>A{<enter><esc>ddO', desc = 'Append curly braces on new line' },
    -- ['ji'] = { '<esc>I<space>', desc = 'Insert at beginning of line with space' },
    ['jI'] = { '<esc>I', desc = 'Insert at beginning of line' },
    ['jo'] = { '<esc>o', desc = 'Open new line below' },
    ['jO'] = { '<esc>ko', desc = 'Open new line above' },
    ['jl'] = { '<esc>la', desc = 'Append at end of line' },
    ['jf'] = { '<esc>A<space>from<space>', desc = 'Append "from" at end of line' },
    ['j0'] = { '<esc>A<space>=<space>', desc = 'Append "= " at end of line' },
    [';;'] = { '<esc>A;<esc>', desc = 'Append semicolon at end of line' },

    -- Snippets
    ['<c-j>'] = { "<cmd>lua require'luasnip'.jump(1)<cr>", desc = 'Jump to next snippet' },
    ['<c-k>'] = { "<cmd>lua require'luasnip'.jump(-1)<cr>", desc = 'Jump to previous snippet' },

    -- Exit insert mode
    ['jj'] = { '<esc>', desc = 'Exit insert mode' },
    ['JJ'] = { '<esc>', desc = 'Exit insert mode' },
    ['kj'] = { '<esc>', desc = 'Exit insert mode' },
    ['<C-u>'] = { '<esc>', desc = 'Exit insert mode' },
    ['KJ'] = { '<esc>', desc = 'Exit insert mode' },
    ['jJ'] = { '<esc><cmd>w!<cr>', desc = 'Save and exit insert mode' },
    ['jp'] = { '<esc>:q!<cr>', desc = 'Quit without saving' },

    -- Save
    ['<C-s>'] = { '<cmd>w<cr><esc>', desc = 'Save file' },
    ['<C-S>'] = { '<cmd>noa w<cr><esc>', desc = 'Save file without autocommands' },

    -- Edit
    ['è'] = { 'p', desc = 'Paste after cursor' },
    ['ò'] = { '#', desc = 'Comment line' },
    ['jy'] = { '<esc>yy<esc>p', desc = 'Yank line and paste' },
    ['jd'] = { '<esc>dd', desc = 'Delete line' },
    ['§'] = { '`', desc = 'Jump to mark' },
    ['<C-Del>'] = { '<C-w>', desc = 'Delete word' },
    ['<C-BS>'] = { '<C-w>', desc = 'Delete word' },

    -- Quit
    ['<C-w>'] = { '<cmd>q<cr>', desc = 'Close window' },
    ['<M-w>'] = { '<cmd>q<cr>', desc = 'Close window' },

    -- Files
    ['<C-e>'] = { '<cmd>Oil<cr>', desc = 'Oil from insert mode' },
  },

  -- Command Mode
  c = {
    ['<C-Del>'] = { '<C-w>', desc = 'Delete word' },
  },

  -- Terminal Mode
  t = {
    -- Escape & Quit
    ['<Esc>'] = { '<C-\\><C-N>', desc = 'Go to normal mode' },
    ['kj'] = { '<C-\\><C-N>', desc = 'Go to normal mode' },
    ['<A-q>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<C-q>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<C-t>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<M-w>'] = { '<C-\\><C-n><cmd>q<cr>', desc = 'Quit' },
    ['<C-u>'] = {
      '<C-\\><C-n><cmd>lua vim.defer_fn(function() vim.api.nvim_input("<leader>") end, 150)<CR>',
      desc = 'Exit terminal mode, wait, and trigger leader',
    },

    -- Window Navigation
    ['<M-o>'] = { '<C-\\><C-n><C-o>', desc = 'Jump back' },
    ['<M-i>'] = { '<C-\\><C-n><C-i>', desc = 'Jump forward' },
    ['<C-h>'] = { '<Cmd>wincmd h<cr><C-\\><C-n>i', desc = 'Move to Left Window' },
    ['<C-k>'] = { '<Cmd>wincmd k<cr>', desc = 'Move to Upper Window' },
    ['<C-l>'] = { '<Cmd>wincmd l<cr><C-\\><C-n>i', desc = 'Move to Right Window' },

    -- Tmux
    ['<A-s>'] = { '<cmd>lua os.execute("tmux split-window -h")<cr>', desc = 'Tmux split right' },
    ['<A-S>'] = { '<cmd>lua os.execute("tmux split-window -v")<cr>', desc = 'Tmux split down' },
    ['<A-j>'] = { '<cmd>lua require("helpers.tmux").move_bottom()<cr>', desc = 'Move to bottom pane (tmux)' },
    ['<A-h>'] = { '<cmd>lua require("tmux").move_left()<cr>', desc = 'Move to left pane (tmux)' },
    ['<A-k>'] = { '<cmd>lua require("tmux").move_top()<cr>', desc = 'Move to top pane (tmux)' },
    ['<A-l>'] = { '<cmd>lua require("tmux").move_right()<cr>', desc = 'Move to right pane (tmux)' },

    -- Run Commands
    ['<M-b>'] = {
      function()
        vim.fn.chansend(vim.b.terminal_job_id, 'make build' .. '\n')
        vim.cmd.startinsert()
      end,
      desc = 'Make build',
    },
    ['<C-y>'] = {
      function()
        vim.fn.chansend(vim.b.terminal_job_id, 'make start' .. '\n')
        vim.cmd.startinsert()
      end,
      desc = 'Make start',
    },
    ['<M-y>'] = {
      function()
        vim.fn.chansend(vim.b.terminal_job_id, 'm' .. '\n')
        vim.cmd.startinsert()
      end,
      desc = 'Run m',
    },
    ['è'] = { 'p', desc = 'Print' },

    -- File Finders
    --TODO: Refactor me out as this is a duplicate of the below
    ['<C-p>'] = {
      function()
        local tmpfile = '/tmp/nvim_term_cwd'
        vim.fn.chansend(vim.b.terminal_job_id, 'pwd > ' .. tmpfile .. ' && clear\n')
        vim.wait(80)

        local cwd = vim.fn.readfile(tmpfile)[1]
        if not cwd then
          print 'Failed to read terminal cwd.'
          return
        end

        local picker_ui = require 'fff.picker_ui'
        local orig_select = picker_ui.select
        local orig_close = picker_ui.close
        local term_win = vim.api.nvim_get_current_win()

        picker_ui.select = function(action)
          picker_ui.select = orig_select
          picker_ui.close = orig_close

          if not picker_ui.state.active then
            return orig_select(action)
          end
          local items = picker_ui.state.filtered_items
          if #items == 0 or picker_ui.state.cursor > #items then
            return orig_select(action)
          end
          local item = items[picker_ui.state.cursor]
          if not item then
            return orig_select(action)
          end

          action = action or 'edit'
          if action ~= 'edit' then
            return orig_select(action)
          end

          local abs_path = vim.fs.normalize(cwd .. '/' .. item.relative_path)
          if not abs_path then
            return orig_select(action)
          end

          vim.cmd 'stopinsert'
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
      desc = 'File finder (fff)',
    },
    ['<C-g>'] = {
      function()
        local tmpfile = '/tmp/nvim_term_cwd'
        vim.fn.chansend(vim.b.terminal_job_id, 'pwd > ' .. tmpfile .. ' && clear\n')
        vim.wait(80)

        local cwd = vim.fn.readfile(tmpfile)[1]
        if not cwd then
          print 'Failed to read terminal cwd.'
          return
        end

        local term_win = vim.api.nvim_get_current_win()
        local actions = require 'telescope.actions'
        local action_state = require 'telescope.actions.state'

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
              if not selection then
                return
              end

              local abs_path = selection.filename or selection[1]
              if not abs_path then
                return
              end
              abs_path = vim.fn.fnamemodify(abs_path, ':p')

              local line = selection.lnum
              local col = selection.col

              actions.close(vim.api.nvim_get_current_buf())

              if _G.NVIM_TERMINAL_ONLY then
                local cmd = 'tmux respawn-pane -k -c ' .. vim.fn.shellescape(cwd) .. ' nvim '
                if line then
                  cmd = cmd .. ' +' .. line
                end
                os.execute(cmd .. vim.fn.shellescape(abs_path))
              else
                pcall(vim.api.nvim_set_current_win, term_win)
                vim.cmd('e! ' .. vim.fn.fnameescape(abs_path))
                if line then
                  vim.api.nvim_win_set_cursor(term_win, { line, (col or 1) - 1 })
                  vim.cmd 'normal! zz'
                end
              end
            end)
            return true
          end,
        }
      end,
      desc = 'Live grep (telescope)',
    },

    -- Misc
    ['<C-^M>'] = { '<NL>', desc = 'New Line' },
    -- ['<C-f>'] = { '<C-\\><C-N><cmd>lua GlobalSnacksPicker()<cr>' },
    -- ['<C-f>'] = { '<C-\\><C-N>/' },
  },

  -- Terminal Normal Mode
  tn = {
    ['<leader>x'] = {
      function()
        local word = vim.fn.expand '<cWORD>'
        vim.notify('chmod +x ' .. word, vim.log.levels.INFO)
        vim.fn.chansend(vim.b.terminal_job_id, 'chmod +x ' .. word .. '\n')
        vim.cmd.startinsert()
      end,
      desc = 'chmod +x',
    },
    ['<M-b>'] = {
      function()
        vim.fn.chansend(vim.b.terminal_job_id, 'make build' .. '\n')
        vim.cmd.startinsert()
      end,
      desc = 'Make build',
    },
    ['<cr>'] = {
      function()
        require('helpers.term_path').handle_enter()
      end,
      desc = 'Open path under cursor',
    },
  },
}
