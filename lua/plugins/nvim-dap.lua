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

    dap.configurations.php = vim.tbl_deep_extend('force', dap.configurations.php or {}, {
      {
        type = 'php',
        request = 'launch',
        name = 'Listen for XDebug',
        log = true, -- Append or override existing values
        port = 9003,
        localSourceRoot = '${workspaceFolder}',
        pathMappings = {
        ['/var/www/app'] = '${workspaceFolder}',
        },
        xdebugSettings = {
          max_children = 512,
          max_data = -1,
          max_depth = 4,
          extended_properties = 1,
        },
        breakpoints = vim.tbl_deep_extend('force', {
          exception = {
            ['*'] = false,
          },
        }, {
          exception = {
            CustomException = true,
          },
        }),
      },
    })

    -- dap.configurations.java = {
    --   {
    --     type = 'java',
    --     request = 'attach',
    --     name = 'Debug (Attach) - Remote',
    --     hostName = '127.0.0.1',
    --     port = 8080,
    --   },
    -- }
    --
    -- dap.adapters.java = function(callback)
    --   -- FIXME:
    --   -- Here a function needs to trigger the `vscode.java.startDebugSession` LSP command
    --   -- The response to the command must be the `port` used below
    --   callback {
    --     type = 'server',
    --     host = '127.0.0.1',
    --     port = '8080',
    --   }
    -- end

    dapui.setup {
      icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
      controls = dap_ui.controls,
    }

    vim.keymap.set('n', '<F5>', dap.continue, { desc = 'Debug: Start/Continue' })
    vim.keymap.set('n', '<leader>dd', dap.continue, { desc = 'Debug: Start/Continue' })
    vim.keymap.set('n', '<C-d>', dap.continue, { desc = 'Debug: Start/Continue' })
    vim.keymap.set('n', '@', dap.continue, { desc = 'Debug: Start/Continue' })
    vim.keymap.set('n', '<F10>', dap.step_over, { desc = 'Debug: Step Over' })
    vim.keymap.set('n', ']', dap.step_over, { desc = 'Debug: Step Over' })
    vim.keymap.set('n', '<F11>', dap.step_into, { desc = 'Debug: Step Into' })
    vim.keymap.set('n', '[', dap.step_into, { desc = 'Debug: Step Into' })
    vim.keymap.set('n', '<F3>', dap.step_out, { desc = 'Debug: Step Out' })
    vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'Debug: Toggle Breakpoint' })
    vim.keymap.set('n', '<leader>du', "<cmd>lua require('dapui').toggle()<cr>", { desc = 'Debug: Toggle Breakpoint' })
    vim.keymap.set('n', '<leader>dh', widgets.hover, { desc = 'Debug: Toggle Breakpoint' })
    vim.keymap.set('n', '<F7>', dapui.toggle, { desc = 'Debug: See last session result.' })
    vim.fn.sign_define('DapBreakpoint', { text = dap_ui.DapBreakpoint, texthl = 'DapLogPoint', linehl = '', numhl = '' })
    vim.fn.sign_define('DapBreakpointCondition', { text = dap_ui.DapBreakpointCondition, texthl = 'DapBreakpointCondition', linehl = '', numhl = '' })
    vim.fn.sign_define('DapBreakpointRejected', { text = dap_ui.DapBreakpointRejected, texthl = 'DapBreakpointRejected', linehl = '', numhl = '' })
    vim.fn.sign_define('DapLogPoint', { text = dap_ui.DapLogPoint, texthl = 'DapLogPoint', linehl = '', numhl = '' })
    vim.fn.sign_define('DapStopped', { text = dap_ui.DapStopped, texthl = 'DapBreakpointCondition', linehl = '', numhl = '' })
    vim.keymap.set('n', '<leader>dc', function()
      dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ')
    end, { desc = 'Debug: Set Breakpoint' })

    -- dap.listeners.after.event_stopped['dapui_config'] = function(session, body)
    --   os.execute '/usr/local/bin/node.exe "C:\\Users\\JFerrara\\Programs\\focus\\focus.js"'
    -- end
    -- dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close
  end,
}
