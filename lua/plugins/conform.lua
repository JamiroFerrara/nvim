return { -- Autoformat
  'stevearc/conform.nvim',
  event = 'VeryLazy', -- TODO:
  keys = {
    {
      '<leader>fb',
      function()
        require('conform').format { async = true, lsp_fallback = true }
      end,
      mode = '',
      desc = '[F]ormat buffer',
    },
  },
  opts = {
    notify_on_error = false,
    formatters_by_ft = {
      lua = { 'stylua' },
    },
  },
}
