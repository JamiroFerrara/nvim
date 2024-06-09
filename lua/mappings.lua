return {
  -- Normal Mode
  n = {
    -- NOTE: Moonlander Specific
    ['|'] = { '1', desc = 'Pipe' },
    ['?'] = { '2', desc = 'Question mark' },
    ['&'] = { '3', desc = 'Ampersand' },
    ['/'] = { '4', desc = 'Slash' },
    ['='] = { '6', desc = 'Equal' },
    ['à'] = { '0', desc = 'Letter a with grave accent' },

    -- Basic Indentation
    ['>'] = { '>>', desc = 'Shift right' },
    ['<'] = { '<<', desc = 'Shift left' },

    -- Leader Shortcuts
    ['<leader>sf'] = { ':%s/\\\\n/\\r/g', desc = 'Search and replace newlines' },
    ['<leader>dB'] = { '<cmd>DBUI<cr>', desc = 'Open DAP UI' },
    ['<leader>c'] = { '<cmd>lua require("Comment.api").toggle.linewise.current()<cr>', desc = 'Toggle comment' },
    ['<leader>mp'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make publish; tmux select-pane -U")<CR>', desc = 'Make publish' },
    ['<leader>mr'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make run; tmux select-pane -U")<CR>', desc = 'Make run' },
    ['<leader>mb'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make build; tmux select-pane -U")<CR>', desc = 'Make build' },
    ['<leader>mt'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make test; tmux select-pane -U")<CR>', desc = 'Make test' },
    ['<leader>ml'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make local; tmux select-pane -U")<CR>', desc = 'Make local' },
    ['<leader>ms'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make start; tmux select-pane -U")<CR>', desc = 'Make start' },
    ['<leader>mw'] = {
      '<cmd>lua os.execute("tmux split-window -v -p 20 make watch; tmux select-pane -U")<CR><cmd>DapContinue<cr>',
      desc = 'Make watch and continue',
    },
    ['<leader>mm'] = { '<cmd>lua os.execute("tmux split-window -v -p 20 make; tmux select-pane -U")<CR>', desc = 'Make' },
    ['<leader>yy'] = { 'GVggy<cmd>q!<CR>', desc = 'Yank all and quit' },
    ['<leader>dd'] = { '<cmd>set ma<cr><cmd>lua require("user.helpers").delete_lines()<CR>', desc = 'Delete lines' },
    ['<leader>tt'] = { '<cmd>TransparentToggle<cr>', desc = 'Toggle transparency' },

    ['<leader>1'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>', desc = 'Navigate to file 1' },
    ['<leader>2'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>', desc = 'Navigate to file 2' },
    ['<leader>3'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>', desc = 'Navigate to file 3' },
    ['<leader>4'] = { '<cmd>lua require("harpoon.ui").nav_file(4)<cr>', desc = 'Navigate to file 4' },
    ['<leader>aa'] = { '<cmd>AerialToggle!<CR>', desc = 'Toggle Aerial' },
    ['<leader>ai'] = { '<cmd>ChatGPT<CR>', desc = 'Chat with GPT' },

    ['<leader>aI'] = { '<cmd>ChatGPTActAs<CR>', desc = 'Chat with GPT acting as' },
    ['<leader>av'] = { '<cmd>lua require("user.helpers").visualModeAi()<CR>', desc = 'Visual mode AI' },
    ['<leader>am'] = { '<cmd>lua require("user.helpers").apiMockAi()<CR>', desc = 'API mock AI' },
    ['<leader>at'] = { '<cmd>lua require("user.helpers").cs2ts()<CR>', desc = 'Convert C# to TypeScript' },
    ['<leader>m'] = { '<cmd>lua require("harpoon.mark").add_file()<cr>', desc = 'Add file to harpoon marks' },
    ['<leader>M'] = { '<cmd>lua require("harpoon.ui").toggle_quick_menu()<cr>', desc = 'Toggle harpoon quick menu' },
    ['<leader><leader>i'] = { '<cmd>IconPickerNormal<cr>', desc = 'Pick icon' },
    ['<leader>ai'] = { '<cmd>ChatGPT<CR>', desc = 'Chat with GPT' },
    ['<leader>aI'] = { '<cmd>ChatGPTActAs<CR>', desc = 'Chat with GPT acting as' },
    ['<leader>av'] = { '<cmd>lua require("user.helpers").visualModeAi()<CR>', desc = 'Visual mode AI' },
    ['<leader>am'] = { '<cmd>lua require("user.helpers").apiMockAi()<CR>', desc = 'API mock AI' },

    ['<leader>at'] = { '<cmd>lua require("user.helpers").cs2ts()<CR>', desc = 'Convert C# to TypeScript' },
    ['<leader><cr>'] = { '<cmd>VimwikiToggleListItem<cr>', desc = 'Toggle Vimwiki list item' },
    ['<leader>ff'] = { '<cmd>Telescope find_files find_command=rg,--ignore,--hidden,--files<cr>', desc = 'Find files' },
    ['<leader>fw'] = { '<cmd>Telescope live_grep find_command=rg,--ignore,--hidden,--files<cr>', desc = 'Live grep' },
    ['<leader>dc'] = { "<cmd>lua require('user.helpers').dap_nodebug()<cr>", desc = 'DAP no debug' },
    ['<leader>ip'] = { '<cmd>IconPickerNormal<cr>', desc = 'Pick icon' },
    ['<leader>q'] = { '<C-\\><C-n>:q<cr>', desc = 'Close all other windows' },
    ['<leader>w'] = { '<cmd>only<cr><cmd>lua os.execute("tmux resize-pane -Z")<cr>', desc = 'Close other windows and maximize current' },
    -- ['<leader>se'] = { '<cmd>lua require("luasnip.loaders").edit_snippet_files()<cr><cr>", desc = 'Edit snippet files' },

    -- TMUX Commands

    ['<leader>th'] = {
      '<cmd>lua os.execute("tmux if-shell \\"[ $(tmux list-panes | wc -l) -eq 1 ]\\" \\"split-window -v -l 10\\" \\"resize-pane -Z\\"")<CR>',
      desc = 'toggle term bottom',
    },
    ['<leader>ap'] = { '<cmd>lua os.execute("/home/jferrara/.scripts/v-script.sh")<CR>', desc = 'toggle term bottom' },

    -- LSP Commands
    ['L'] = { '<cmd>lua vim.lsp.buf.hover()<cr>' },

    -- Git Commands

    ['<leader>gj'] = { '<cmd>lua require("gitsigns").next_hunk()<cr>' },
    ['<leader>gk'] = { '<cmd>lua require("gitsigns").prev_hunk()<cr>' },
    ['<leader>gl'] = { '<cmd>lua require("gitsigns").blame_line()<cr>' },
    ['<leader>gp'] = { '<cmd>lua require("gitsigns").preview_hunk()<cr>' },
    ['<leader>gh'] = { '<cmd>lua require("gitsigns").reset_hunk()<cr>' },
    ['<leader>gr'] = { '<cmd>lua require("gitsigns").reset_buffer()<cr>' },
    ['<leader>gs'] = { '<cmd>lua require("gitsigns").stage_hunk()<cr>' },
    ['<leader>gu'] = { '<cmd>lua require("gitsigns").undo_stage_hunk()<cr>' },

    ['<leader>gd'] = { '<cmd>lua require("gitsigns").diffthis()<cr>' },

    -- Quick Actions
    ['<A-o>'] = { '<C-o>', desc = '' },

    ['<A-i>'] = { '<C-i>', desc = '' },

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

    -- Navigation
    ['<leader>ai'] = { '<cmd>ChatGPT<CR>' },
    ['<leader>aI'] = { '<cmd>ChatGPTActAs<CR>' },
    ['<leader>av'] = { '<cmd>lua require("user.helpers").visualModeAi()<CR>' },
    ['<leader>am'] = { '<cmd>lua require("user.helpers").apiMockAi()<CR>' },
    ['<leader>at'] = { '<cmd>lua require("user.helpers").cs2ts()<CR>' },

    -- Harpoon
    ['<leader>m'] = { '<cmd>lua require("harpoon.mark").add_file()<cr>' },
    ['<leader>M'] = { '<cmd>lua require("harpoon.ui").toggle_quick_menu()<cr>' },
    ['<leader>1'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>' },
    ['<C-w>'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>' },
    ['<leader>2'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>' },
    ['<C-e>'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>' },
    ['<leader>3'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>' },
    ['<C-r>'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>' },
    ['<leader>4'] = { '<cmd>lua require("harpoon.ui").nav_file(4)<cr>' },

    -- Other
    ['<leader>yy'] = { 'GVggy<cmd>q!<CR>' },
    ['|'] = { '1' },
    ['?'] = { '2' },
    ['&'] = { '3' },
    ['/'] = { '4' },
    ['='] = { '6' },
    -- ['['] = { '7' },

    -- [']'] = { '8' },
    ['+'] = { '<cmd>e#<cr>' },
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

    ['<leader>oo'] = { 'za' },
    ['<leader>oc'] = { '<cmd>AerialTreeSyncFolds<cr>zRzm' },
    ['<leader>oa'] = { '<cmd>AerialTreeSyncFolds<cr>zRjk' },
    ['<leader>P'] = { ':Prettier<cr>' },
    ['<leader>bd'] = { "<cmd>lua require('user.helpers').dotnet_run()<cr>" },
    ['<leader>bt'] = { '<cmd>lua require("user.helpers").dotnet_test()<CR>' },
    ['<leader>bn'] = { "<cmd>lua require('user.helpers').npm_start()<cr>" },
    ['<leader>bp'] = { "<cmd>lua require('user.helpers').publish()<cr>" },
    ['<leader>bl'] = { "<cmd>lua require('user.helpers').npm_start_local()<cr>" },
    ['<A-r>'] = { "<cmd>lua require('zen-mode').toggle({window= {width = 1}})<cr>" },

    ['<C-t>'] = { '<cmd>vsplit<cr><cmd> e TODO.md<cr>', nowait = true },
    ['<A-t>'] = { '<cmd>vsplit<cr><cmd> e TODO.md<cr>' },

    ['<C-g>'] = { '<cmd>ToggleTerm size=10 direction=horizontal<cr>' },
    ['<C-p>'] = { '<cmd>Telescope find_files<cr>' },
    ['<C-P>'] = { '<cmd>Telescope buffers<cr>' },
    ['gr'] = { '<cmd>Glance references<cr>' },
    ['<leader>fb'] = { '<cmd>Telescope current_buffer_fuzzy_find<cr>' },
    ['<leader>ft'] = { '<cmd>TodoTelescope<cr>' },
    ['<C-f>'] = { '<cmd>Telescope current_buffer_fuzzy_find<cr>' },
    ['<leader>lc'] = {
      "<cmd>lua vim.diagnostic.open_float()<cr><cmd>lua vim.diagnostic.open_float()<cr>wwy$<cmd>sleep 10ms<cr><cmd>:q<cr><cmd>lua require('user.helpers').search_chrome_yank()<cr>",
    },
    ['<leader>le'] = { '<cmd>lua vim.diagnostic.goto_next()<cr>' },
    ['<leader>lr'] = { '<cmd>vim.lsp.buf.rename()<cr>' },
    ['<A-e>'] = { '<cmd>w<cr>' },
    ['<leader>hr'] = { "<cmd>lua require('user/react-helpers').commands()<cr>" },
    ['<leader>hg'] = { "<cmd>lua require('user/git').commands()<cr>" },
    ['<leader>hj'] = { "<cmd>lua require('user/jira-helpers').commands()<cr>" },
    ['<C-j>'] = { '<C-w>j' },
    ['<C-h>'] = { '<C-w>h' },
    ['<C-k>'] = { '<C-w>k' },
    ['<C-l>'] = { '<C-w>l' },
    ['<A-j>'] = { '<cmd>wincmd j<cr>' },
    ['<A-h>'] = { '<cmd>wincmd h<cr>' },
    ['<A-k>'] = { '<C-w>k' },
    ['<A-l>'] = { '<C-w>l' },
    ['<A-s>'] = { ':vsp<cr>:sleep 50m<cr><C-o>' },
    ['<A-S>'] = { ':sp<cr>:sleep 50m<cr><C-o>' },
    ["'"] = { '$' },
    ['0'] = { '^' },
    ['t'] = { 'f' },
    ['T'] = { 't' },

    ['<leader>0'] = { 'f=w' },

    ['<leader>='] = { 'F=F=w' },
    ['caè'] = { 'ca{' },
    ['ciè'] = { 'ci{' },

    ['vaè'] = { 'va{' },
    ['viè'] = { 'vi{' },
    ['ci8'] = { 'ci(' },
    ['va8'] = { 'va(' },
    ['vi8'] = { 'vi(' },
    ['ca8'] = { 'ca(' },
    ['tè'] = { 'f{' },
    ['Tè'] = { '{' },
    ['vw'] = { 've' },
    ['vtè'] = { 'vt{' },
    ['vt8'] = { 'vt(' },
    ['<bs>'] = { 'b' },
    ['<esc>'] = { '0' },
    ['s'] = { '/' },
    ['Q'] = { '@' },

    ['<leader><leader>'] = { '@' },
    ['X'] = { 's' },
    ['<leader>se'] = { '<cmd>lua require("luasnip.loaders").edit_snippet_files()<cr><cr>")' },
    ['<leader>ip'] = { '<cmd>IconPickerNormal<cr>' },
    ['<leader>q'] = { '<C-\\><C-n>:q<cr>' },
    ['<leader>w'] = { '<cmd>only<cr><cmd>lua os.execute("tmux resize-pane -Z")<cr>' },
    ['<A-w>'] = { '<cmd>q<cr><cmd>Telescope quickfix<cr>' },

    ['H'] = { '<cmd>lua require("user.helpers").jprev()<cr>' },
  },

  -- Visual Mode
  v = {
    -- NOTE: Moonlander specifc
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
    ['<leader>qc'] = { ':!quicktype --features just-types -l csharp<CR>', desc = 'Run quicktype for C#' },
    ['<leader>av'] = { 'y<cmd>lua require("user.helpers").visualModeAi()<CR>', desc = 'Visual mode AI' },

    ['<leader>al'] = { '<cmd>lua require "align".align_to_char(1, true)<cr>', desc = 'Align to character' },
    ['<leader>aw'] = { '<cmd>lua require "align".align_to_string(false, true, true)<cr>', desc = 'Align to string' },

    ['<leader>c'] = { "<esc><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<cr>", desc = 'Toggle comment' },
  },
}
