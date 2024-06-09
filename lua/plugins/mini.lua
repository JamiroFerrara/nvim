return { -- Collection of various small independent plugins/modules
  'echasnovski/mini.nvim',
  mappings = {
    n = {
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
      ['di8'] = { 'di(' },
      ['da8'] = { 'da(' },
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
    },
    v = {
      ['è'] = { 'p', desc = '' },
      ['<'] = { '<gv', desc = '' },
      ['>'] = { '>gv', desc = '' },
      ['ga'] = { '%', desc = '' },
      ['gA'] = { '%%', desc = '' },
      ['y'] = { 'myy`y', desc = '' },
      ['Y'] = { 'myY`y', desc = '' },
      ["'"] = { "xi''<esc>hp", desc = '' },
    },
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
  },
  config = function()
    -- Better Around/Inside textobjects
    --
    -- Examples:
    --  - va)  - [V]isually select [A]round [)]paren
    --  - yinq - [Y]ank [I]nside [N]ext [']quote
    --  - ci'  - [C]hange [I]nside [']quote
    local gen_spec = require('mini.ai').gen_spec
    require('mini.ai').setup {
      n_lines = 500,
      custom_textobjects = {
        f = gen_spec.treesitter { a = '@function.outer', i = '@function.inner' },
      },
    }

    local map_ai_move = function(lhs, textobject_id, direction, desc)
      local rhs = function()
        MiniAi.move_cursor('left', 'a', textobject_id, { search_method = direction })
      end
      vim.keymap.set({ 'n', 'x', 'o' }, lhs, rhs, { desc = desc })
    end

    -- Instead of `'f'` use id of textobject you'd like to move.
    -- For more info see `:h MiniAi.move_cursor()`.
    map_ai_move('Â°', 'f', 'prev', 'Jump to prev function')
    map_ai_move('Ã¹', 'f', 'next', 'Jump to next function')

    -- Add/delete/replace surroundings (brackets, quotes, etc.)
    --
    -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
    -- - sd'   - [S]urround [D]elete [']quotes
    -- - sr)'  - [S]urround [R]eplace [)] [']
    -- FIX: Currently overritten by lightspeed
    require('mini.surround').setup()

    local statusline = require 'mini.statusline'
    statusline.setup { use_icons = vim.g.have_nerd_font }

    -- You can configure sections in the statusline by overriding their
    -- default behavior. For example, here we set the section for
    -- cursor location to LINE:COLUMN
    ---@diagnostic disable-next-line: duplicate-set-field
    statusline.section_location = function()
      return '%2l:%-2v'
    end
  end,
}
