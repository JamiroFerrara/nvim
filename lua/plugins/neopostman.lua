return {
  {
    'JamiroFerrara/neopostman.nvim',
    event = 'VeryLazy',
    cmd = {
      "Neogrep",
      "NeogrepToggle",
      "NeogrepWord",
      "NeogrepBuffer",
      "TmuxSessions",
      "NeoMake",
      "Neogithub",
      "NeoNotifications",
      "Neopostman"
    },
    dependencies = { 'MunifTanjim/nui.nvim' },
    config = function()
      require('neopostman').setup {}
      vim.keymap.set('n', '<leader>po', '<cmd>Neopostman<cr>', { noremap = true, silent = true })
      vim.keymap.set('n', '<leader>gh', '<cmd>Neogithub<cr>', { noremap = true, silent = true })

      vim.keymap.set('n', '<leader>mm', '<cmd>Neomake<cr>', { noremap = true, silent = true })
      vim.keymap.set('n', '<leader>mM', '<cmd>NeoMake<cr>', { noremap = true, silent = true })
      -- vim.keymap.set('n', '<C-g>', '<cmd>Neogrep<cr>', { noremap = true, silent = true })
      -- vim.keymap.set('t', '<C-g>', '<cmd>Neogrep<cr>', { noremap = true, silent = true })
      -- vim.keymap.set('n', '<leader>fc', '<cmd>NeogrepWord<cr>', { noremap = true, silent = true })
      vim.keymap.set('n', '<C-n>', '<cmd>NeogrepWord<cr>', { noremap = true, silent = true })
      vim.keymap.set('n', '<leader>fW', '<cmd>NeogrepBuffer<cr>', { noremap = true, silent = true })
      -- vim.keymap.set('n', '<C-f>', '<cmd>NeogrepBuffer<cr>', { noremap = true, silent = true })

      vim.keymap.set('n', '<leader>dd', '<cmd>FilterBuffer<cr>', { noremap = true, silent = true })
    end,
  },
}
