return {
  'dmtrKovalenko/fff.nvim',
  build = function()
    -- downloads a prebuilt binary or falls back to cargo build
    require("fff.download").download_or_build_binary()
  end,
  -- for nixos:
  -- build = "nix run .#release",
  opts = {
    debug = {
      enabled = false,
      show_scores = false,
    },
    keymaps = {
      close = 'kj',
      select = '<CR>',
      select_split = '<C-s>',
      select_vsplit = '<C-v>',
      select_tab = '<C-t>',
      move_up = { '<Up>', '<C-p>', '<C-k>' },
      move_down = { '<Down>', '<C-n>', '<C-j>' },
      preview_scroll_up = '<C-u>',
      preview_scroll_down = '<C-d>',
      toggle_debug = '<F2>',
      cycle_grep_modes = '<S-Tab>',
      cycle_previous_query = '<C-Up>',
      toggle_select = '<Tab>',
      send_to_quickfix = '<C-q>',
      focus_list = '<leader>l',
      focus_preview = '<leader>p',
    },
    layout = {
      height = 1,
      width = 1,
      prompt_position = 'top',  -- or 'top'
      preview_position = 'top', -- 'left' | 'right' | 'top' | 'bottom'
      preview_size = 0.5,
      flex = { size = 130, wrap = 'top' },
      show_scrollbar = true,
      show_full_path = true, -- Set to true to show full paths instead of filename + directory
      path_shorten_strategy = 'middle_number', -- 'middle_number' | 'middle' | 'end'
      anchor = 'center',
    },
    preview = {
      enabled = true,
      max_size = 10 * 1024 * 1024,
      chunk_size = 8192,
      binary_file_threshold = 1024,
      imagemagick_info_format_str = '%m: %wx%h, %[colorspace], %q-bit',
      line_numbers = false,
      cursorlineopt = 'both',
      wrap_lines = false,
      filetypes = {
        svg = { wrap_lines = true },
        markdown = { wrap_lines = false },
        text = { wrap_lines = false },
      },
    },
    frecency = {
      enabled = true,
      db_path = vim.fn.stdpath('cache') .. '/fff_nvim',
    },
    history = {
      enabled = true,
      db_path = vim.fn.stdpath('data') .. '/fff_queries',
      min_combo_count = 3,
      combo_boost_score_multiplier = 100,
    },
  },
  lazy = false, -- the plugin lazy-initialises itself
  keys = {
    { "<C-p>", function() require('fff').find_files() end, desc = 'FFFind files' },
    -- { "<C-g>", function() require('fff').live_grep() end,  desc = 'LiFFFe grep' },
    -- {
    --   "<C-g>",
    --   function() require('fff').live_grep({ grep = { modes = { 'fuzzy', 'plain' } } }) end,
    --   desc = 'Live fffuzy grep',
    -- },
    -- {
    --   "<C-n>",
    --   function() require('fff').live_grep({ query = vim.fn.expand("<cword>") }) end,
    --   desc = 'Search current word',
    -- },
  },
}
