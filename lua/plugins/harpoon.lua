return {
  'ThePrimeagen/harpoon',
  event = 'VeryLazy',
  mappings = {
    n = {
      ['<leader>1'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>', desc = 'Navigate to file 1' },
      ['<leader>2'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>', desc = 'Navigate to file 2' },
      ['<leader>3'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>', desc = 'Navigate to file 3' },
      ['<leader>4'] = { '<cmd>lua require("harpoon.ui").nav_file(4)<cr>', desc = 'Navigate to file 4' },
      ['<leader>m'] = { '<cmd>lua require("harpoon.mark").add_file()<cr>', desc = 'Add file to harpoon marks' },
      ['<leader>M'] = { '<cmd>lua require("harpoon.ui").toggle_quick_menu()<cr>', desc = 'Toggle harpoon quick menu' },
    },
  },
}
