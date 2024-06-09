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
