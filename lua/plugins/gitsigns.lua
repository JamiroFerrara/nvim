return { -- Adds git related signs to the gutter, as well as utilities for managing changes
  'lewis6991/gitsigns.nvim',
  -- lazy = 'BufReadPre',
  mappings = {
    n = {
      ['<leader>gj'] = { '<cmd>lua require("gitsigns").next_hunk()<cr>' },
      ['<leader>gk'] = { '<cmd>lua require("gitsigns").prev_hunk()<cr>' },
      ['<leader>gl'] = { '<cmd>lua require("gitsigns").blame_line()<cr>' },
      ['<leader>gp'] = { '<cmd>lua require("gitsigns").preview_hunk()<cr>' },
      ['<leader>gh'] = { '<cmd>lua require("gitsigns").reset_hunk()<cr>' },
      ['<leader>gr'] = { '<cmd>lua require("gitsigns").reset_buffer()<cr>' },
      ['<leader>gs'] = { '<cmd>lua require("gitsigns").stage_hunk()<cr>' },
      ['<leader>gu'] = { '<cmd>lua require("gitsigns").undo_stage_hunk()<cr>' },
      ['<leader>gd'] = { '<cmd>lua require("gitsigns").diffthis()<cr>' },
    },
  },
  opts = {
    -- signs                        = {
    --   add          = { text = '│' },
    --   change       = { text = '│' },
    --   delete       = { text = '_' },
    --   topdelete    = { text = '‾' },
    --   changedelete = { text = '~' },
    --   untracked    = { text = '┆' },
    -- },
    signcolumn = true, -- Toggle with `:Gitsigns toggle_signs`
    numhl = true, -- Toggle with `:Gitsigns toggle_numhl`
    linehl = false, -- Toggle with `:Gitsigns toggle_linehl`
    word_diff = false, -- Toggle with `:Gitsigns toggle_word_diff`
    watch_gitdir = {
      interval = 1000,
      follow_files = true,
    },
    attach_to_untracked = true,
    current_line_blame = true, -- Toggle with `:Gitsigns toggle_current_line_blame`
    current_line_blame_opts = {
      virt_text = true,
      virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
      delay = 1000,
      ignore_whitespace = false,
    },
    current_line_blame_formatter = '<author>, <author_time:%Y-%m-%d> - <summary>',
    sign_priority = 6,
    update_debounce = 100,
    status_formatter = nil, -- Use default
    max_file_length = 40000, -- Disable if file is longer than this (in lines)
  },
}
