return { -- Adds git related signs to the gutter, as well as utilities for managing changes
  'lewis6991/gitsigns.nvim',
  -- lazy = 'BufReadPre',
  mappings = {
    n = {
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
