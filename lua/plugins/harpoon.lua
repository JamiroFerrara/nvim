return {
  'ThePrimeagen/harpoon',
  event = 'VeryLazy',
  mappings = {
    n = {
      -- Harpoon
      ['<leader>m'] = { '<cmd>lua require("harpoon.mark").add_file()<cr>' },
      ['<leader>M'] = { '<cmd>lua require("harpoon.ui").toggle_quick_menu()<cr>' },
      ['<leader>1'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>' },
      ['<C-w>'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>' },
      ['<leader>2'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>' },
      ['<C-e>'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>' },
      ['<leader>3'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>' },
      -- ['<C-r>'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>' },
      ['<leader>4'] = { '<cmd>lua require("harpoon.ui").nav_file(4)<cr>' },
    },
  },
}
