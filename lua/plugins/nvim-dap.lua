---@diagnostic disable: missing-fields
local dap_ui = require('../ui').dap_ui

return {
  -- NOTE: Yes, you can install new plugins here!
  'mfussenegger/nvim-dap',
  lazy = true,
  -- NOTE: And you can specify dependencies as well
  dependencies = {
    'rcarriga/nvim-dap-ui',
    'nvim-neotest/nvim-nio',
    'williamboman/mason.nvim',
    'jay-babu/mason-nvim-dap.nvim',
    'leoluz/nvim-dap-go',
  },
  config = function()
    local dap = require 'dap'
    local dapui = require 'dapui'
    local widgets = require 'dap.ui.widgets'

    require('mason-nvim-dap').setup {
      -- You can provide additional configuration to the handlers,
      -- see mason-nvim-dap README for more information
      handlers = {},
      automatic_installation = true,
      ensure_installed = {
        -- Update this to ensure that you have the debuggers for the langs you want
        'typescript-language-server',
        'chrome-debug-adapter',
        'eslint-lsp',
        'intelephense',
        'lua-language-server',
        'netcoredbg',
        'omnisharp',
        'php-debug-adapter',
        'prettier',
        'sql-formatter',
        'stylua',
        'sqls',
      },
    }

    dapui.setup {
      icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
      controls = dap_ui.controls,
    }

    vim.keymap.set('n', '<F5>', dap.continue, { desc = 'Debug: Start/Continue' })
    vim.keymap.set('n', '<F10>', dap.step_over, { desc = 'Debug: Step Over' })
    vim.keymap.set('n', '<F11>', dap.step_into, { desc = 'Debug: Step Into' })
    vim.keymap.set('n', '<F3>', dap.step_out, { desc = 'Debug: Step Out' })
    vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'Debug: Toggle Breakpoint' })
    vim.keymap.set('n', '<leader>dh', widgets.hover, { desc = 'Debug: Toggle Breakpoint' })
    vim.keymap.set('n', '<F7>', dapui.toggle, { desc = 'Debug: See last session result.' })
    vim.fn.sign_define('DapBreakpoint', { text = dap_ui.DapBreakpoint, texthl = 'DapLogPoint', linehl = '', numhl = '' })
    vim.fn.sign_define('DapBreakpointCondition', { text = dap_ui.DapBreakpointCondition, texthl = 'DapBreakpointCondition', linehl = '', numhl = '' })
    vim.fn.sign_define('DapBreakpointRejected', { text = dap_ui.DapBreakpointRejected, texthl = 'DapBreakpointRejected', linehl = '', numhl = '' })
    vim.fn.sign_define('DapLogPoint', { text = dap_ui.DapLogPoint, texthl = 'DapLogPoint', linehl = '', numhl = '' })
    vim.fn.sign_define('DapStopped', { text = dap_ui.DapStopped, texthl = 'DapBreakpointCondition', linehl = '', numhl = '' })
    vim.keymap.set('n', '<leader>B', function()
      dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ')
    end, { desc = 'Debug: Set Breakpoint' })

    dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close
  end,
}
