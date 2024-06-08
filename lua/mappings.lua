return {
  -- Normal Mode
  n = {
    -- Basic Indentation
    ['>'] = { '>>', desc = 'Shift right' },
    ['<'] = { '<<', desc = 'Shift left' },
    ['|'] = { '1', desc = 'Pipe' },
    ['?'] = { '2', desc = 'Question mark' },
    ['&'] = { '3', desc = 'Ampersand' },
    ['/'] = { '4', desc = 'Slash' },
    ['='] = { '6', desc = 'Equal' },
    ['['] = { '7', desc = 'Opening square bracket' },
    [']'] = { '8', desc = 'Closing square bracket' },
    ['à'] = { '0', desc = 'Letter a with grave accent' },

    -- Leader Shortcuts
    ['<leader>sf'] = { ':%s/\\\\n/\\r/g', desc = 'Search and replace newlines' },
    ['<leader>e'] = { '<cmd>Neotree toggle<cr>', desc = 'Toggle Neotree' },
    ['<leader>gg'] = { '<cmd>lua os.execute("tmux neww lazygit")<cr>', desc = 'Open lazygit in a new tmux window' },
    ['<leader>lg'] = { '<cmd>lua os.execute("tmux neww lazygit")<cr>', desc = 'Open lazygit in a new tmux window' },
    ['<leader>gj'] = { '<cmd>lua require("gitsigns").next_hunk()<cr>', desc = 'Go to next git hunk' },
    ['<leader>gk'] = { '<cmd>lua require("gitsigns").prev_hunk()<cr>', desc = 'Go to previous git hunk' },
    ['<leader>gl'] = { '<cmd>lua require("gitsigns").blame_line()<cr>', desc = 'Blame current line' },
    ['<leader>gp'] = { '<cmd>lua require("gitsigns").preview_hunk()<cr>', desc = 'Preview git hunk' },
    ['<leader>gh'] = { '<cmd>lua require("gitsigns").reset_hunk()<cr>', desc = 'Reset git hunk' },
    ['<leader>gr'] = { '<cmd>lua require("gitsigns").reset_buffer()<cr>', desc = 'Reset git buffer' },
    ['<leader>gs'] = { '<cmd>lua require("gitsigns").stage_hunk()<cr>', desc = 'Stage git hunk' },
    ['<leader>gu'] = { '<cmd>lua require("gitsigns").undo_stage_hunk()<cr>', desc = 'Undo stage git hunk' },
    ['<leader>gd'] = { '<cmd>lua require("gitsigns").diffthis()<cr>', desc = 'Diff current file' },
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
    ['['] = { '7' },

    [']'] = { '8' },
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

  -- Terminal Mode
  t = {
    ['è'] = { 'p', desc = 'Print' },
    ['<esc>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<A-s>'] = { '<cmd>2ToggleTerm<cr>', desc = 'Toggle Terminal' },
    ['<C-s>'] = { '<cmd>2ToggleTerm<cr>', desc = 'Toggle Terminal' },
    ['q'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    -- ['j'] = false,
    ['<C-^M>'] = { '<NL>', desc = 'New Line' },
    ['<leader>q'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<A-q>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<C-t>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<C-g>'] = { '<C-\\><C-n>:q<cr>', desc = 'Quit' },
    ['<C-j>'] = { '<NL>', desc = 'New Line' },
    ['<C-h>'] = { '<Cmd>wincmd h<cr><C-\\><C-n>i', desc = 'Move to Left Window' },

    ['<C-k>'] = { '<Cmd>wincmd k<cr>', desc = 'Move to Upper Window' },
    ['<C-l>'] = { '<Cmd>wincmd l<cr><C-\\><C-n>i', desc = 'Move to Right Window' },
    ['<A-j>'] = { '<NL>', desc = 'New Line' },
    ['<A-h>'] = { '<Cmd>wincmd h<cr><C-\\><C-n>i', desc = 'Move to Left Window' },
    ['<A-k>'] = { '<Cmd>wincmd k<cr>', desc = 'Move to Upper Window' },

    ['<A-l>'] = { '<Cmd>wincmd l<cr><C-\\><C-n>i', desc = 'Move to Right Window' },
  },

  -- Visual Mode
  v = {
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
    ['<leader>ai'] = { '<cmd>ChatGPTEditWithInstructions<CR>', desc = 'Edit with instructions' },
    ['<leader>ao'] = { '<cmd>ChatGPTRun organize_code<CR>', desc = 'Organize code' },
    ['<leader>aO'] = { '<cmd>ChatGPTRun optimize_code<CR>', desc = 'Optimize code' },
    ['<leader>ac'] = { '<cmd>ChatGPTRun complete_code<CR>', desc = 'Complete code' },
    ['<leader>at'] = { '<cmd>ChatGPTRun translate<CR>', desc = 'Translate code' },
    ['<leader>as'] = { '<cmd>ChatGPTRun summerize<CR>', desc = 'Summerize code' },
    ['<leader>af'] = { '<cmd>ChatGPTRun fix_bugs<CR>', desc = 'Fix bugs' },
    ['<leader>ae'] = { '<cmd>ChatGPTRun explain_code<CR>', desc = 'Explain code' },
    ['<leader>ar'] = { '<cmd>ChatGPTRun code_readability_analysis<CR>', desc = 'Analyze code readability' },

    -- NOTE: [ Ai Conversions ]
    ['<leader>aCt'] = { '<cmd>ChatGPTRun convert_typescript<CR>', desc = 'Convert to TypeScript' },
    ['<leader>aCb'] = { '<cmd>ChatGPTRun convert_bash<CR>', desc = 'Convert to Bash' },
    ['<leader>aCc'] = { '<cmd>ChatGPTRun convert_cs<CR>', desc = 'Convert to C#' },
    ['<leader>aCp'] = { '<cmd>ChatGPTRun convert_php<CR>', desc = 'Convert to PHP' },
    ['<leader>aCl'] = { '<cmd>ChatGPTRun convert_lua<CR>', desc = 'Convert to Lua' },

    ['<leader>qc'] = { ':!quicktype --features just-types -l csharp<CR>', desc = 'Run quicktype for C#' },
    ['<leader>av'] = { 'y<cmd>lua require("user.helpers").visualModeAi()<CR>', desc = 'Visual mode AI' },

    ['<leader>al'] = { '<cmd>lua require "align".align_to_char(1, true)<cr>', desc = 'Align to character' },
    ['<leader>aw'] = { '<cmd>lua require "align".align_to_string(false, true, true)<cr>', desc = 'Align to string' },

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
    ['jJ'] = { '<esc><cmd>w!<cr>', desc = 'Save and exit insert mode' },
    ['jp'] = { '<esc>:q!<cr>', desc = 'Quit without saving' },
    ['jk'] = { '<esc>A', desc = 'Append at end of line' },
    ['jK'] = { '<esc>A<space>', desc = 'Append at end of line with space' },
    ['jè'] = { '<esc>A{<enter><esc>ddO', desc = 'Append curly braces on new line' },
    ['ji'] = { '<esc>I<space>', desc = 'Insert at beginning of line with space' },
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
  },
}
