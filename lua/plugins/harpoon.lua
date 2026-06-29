-- TODO: Lazy load this better
return {
  'ThePrimeagen/harpoon',
  event = 'VeryLazy',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  mappings = {
    n = {
      -- Harpoon
      ['<leader>m'] = { '<cmd>lua require("harpoon.mark").add_file()<cr>' },
      ['<leader>M'] = { '<cmd>lua require("harpoon.ui").toggle_quick_menu()<cr>' },
      ['<leader>1'] = { '<cmd>lua require("harpoon.ui").nav_file(1)<cr>' },
      ['<leader>2'] = { '<cmd>lua require("harpoon.ui").nav_file(2)<cr>' },
      ['<leader>3'] = { '<cmd>lua require("harpoon.ui").nav_file(3)<cr>' },
      ['<leader>4'] = { '<cmd>lua require("harpoon.ui").nav_file(4)<cr>' },
    },
  },
}
