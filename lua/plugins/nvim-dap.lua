---@diagnostic disable: missing-fields
local dap_ui = require('../ui').dap_ui

return {
  -- NOTE: Yes, you can install new plugins here!
  'mfussenegger/nvim-dap',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  lazy = true,
  keys = {
    { '<F5>',     function() require('dap').continue() end,             desc = 'Debug: Start/Continue' },
    { '<C-d>',    function() require('dap').continue() end,             desc = 'Debug: Start/Continue' },
    { '@',        function() require('dap').continue() end,             desc = 'Debug: Start/Continue' },
    { '<F10>',    function() require('dap').step_over() end,            desc = 'Debug: Step Over' },
    { ']',        function() require('dap').step_over() end,            desc = 'Debug: Step Over' },
    { '<F11>',    function() require('dap').step_into() end,            desc = 'Debug: Step Into' },
    { '[',        function() require('dap').step_into() end,            desc = 'Debug: Step Into' },
    { '<F3>',     function() require('dap').step_out() end,             desc = 'Debug: Step Out' },
    { '<leader>db', function() require('dap').toggle_breakpoint() end,  desc = 'Debug: Toggle Breakpoint' },
    { '<leader>dc', function() require('dap').set_breakpoint(vim.fn.input 'Breakpoint condition: ') end, desc = 'Debug: Conditional Breakpoint' },
    { '<leader>du', '<cmd>lua require("dapui").toggle()<cr>',           desc = 'Debug: Toggle UI' },
    { '<leader>dh', function() require('dap.ui.widgets').hover() end,   desc = 'Debug: Hover' },
    { '<leader>df', function() require('dap.ext.fuzzy_hover').fuzzy_hover() end, desc = 'Debug: Fuzzy Hover' },
    { '<F7>',     function() require('dapui').toggle() end,             desc = 'Debug: Toggle UI' },
    { '<leader>dw', function()
      local workingDir = vim.fn.getcwd()
      vim.cmd('e ' .. workingDir .. '/DAP\\ Watches')
    end, desc = 'Debug: Open Watches' },
    { '<leader>ds', function()
      local workingDir = vim.fn.getcwd()
      vim.cmd('e ' .. workingDir .. '/DAP\\ Scopes')
    end, desc = 'Debug: Open Scopes' },
  },
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

    require('mason-nvim-dap').setup {
      -- You can provide additional configuration to the handlers,
      -- see mason-nvim-dap README for more information
      -- {
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

    -- print(vim.inspect(dap.configurations.javascript))
    -- dap.configurations.javascript = vim.tbl_deep_extend('force', dap.configurations.javascript or {}, {
    --   {
    --     type = 'chrome',
    --     request = 'attach',
    --     name = 'Launch Node.exe',
    --     program = '${file}',
    --     cwd = '${workspaceFolder}',
    --     runtimeExecutable = '/mnt/c/Users/JFerrara/.bun/bin/bun.exe`'
    --   },
    -- })
    -- dap.configurations.typescript = dap.configurations.javascript


    dap.configurations.cs = {
      {
        cwd = '${fileDirname}',
        name = 'NetCoreDbg: Launch',
        program = function()
          return require('helpers.nvim-dap-dotnet').build_dll_path()
        end,
        request = 'launch',
        type = 'coreclr',
        env = {
          ASPNETCORE_ENVIRONMENT = function()
            return "DEVE"
          end,
          ASPNETCORE_URLS = function()
            return "http://localhost:8000"
          end,
        },
      },
    }

    dap.configurations.php = vim.tbl_deep_extend('force', dap.configurations.php or {}, {
      {
        type = 'php',
        request = 'launch',
        name = 'Listen for XDebug',
        log = false,
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
        -- breakpoints = vim.tbl_deep_extend('force', {
        --   exception = {
        --     ['*'] = false,
        --   },
        -- }, {
        --   exception = {
        --     CustomException = true,
        --   },
        -- }),
      },
    })

    dap.configurations.java = {
      {
        type = 'java',
        request = 'attach',
        name = 'Debug (Attach) - Remote',
        hostName = '127.0.0.1',
        port = 8080,
      },
    }

    dap.adapters.java = function(callback)
      -- FIXME:
      -- Here a function needs to trigger the `vscode.java.startDebugSession` LSP command
      -- The response to the command must be the `port` used below
      callback {
        type = 'server',
        host = '127.0.0.1',
        port = '8080',
      }
    end

    dapui.setup {
      expand_lines = true,
      controls = { enabled = false }, -- no extra play/step buttons
      floating = { border = "rounded" },

      -- Set dapui window
      render = {
        max_type_length = 60,
        max_value_lines = 200,
      },

      -- Only one layout: just the "scopes" (variables) list at the bottom
      layouts = {
        {
          elements = {
            { id = "scopes",  size = 0.5 }, -- 100% of this panel is scopes
            { id = "watches", size = 0.5 }, -- 100% of this panel is scopes
            { id = "repl",    size = 0.1 }
          },
          size = 15,           -- height in lines (adjust to taste)
          position = "bottom", -- "left", "right", "top", "bottom"
        },
      },
    }

    --   NOTE: Original version
    --   layouts = { {
    --   elements = { {
    --       id = "scopes",
    --       size = 0.25
    --     }, {
    --       id = "breakpoints",
    --       size = 0.25
    --     }, {
    --       id = "stacks",
    --       size = 0.25
    --     }, {
    --       id = "watches",
    --       size = 0.25
    --     } },
    --   position = "left",
    --   size = 40
    -- }, {
    --   elements = { {
    --       id = "repl",
    --       size = 0.5
    --     }, {
    --       id = "console",
    --       size = 0.5
    --     } },
    --   position = "bottom",
    --   size = 10
    -- } },



    vim.fn.sign_define('DapBreakpoint', { text = dap_ui.DapBreakpoint, texthl = 'DapLogPoint', linehl = '', numhl = '', priority = 50 })
    vim.fn.sign_define('DapBreakpointCondition',
      { text = dap_ui.DapBreakpointCondition, texthl = 'DapBreakpointCondition', linehl = '', numhl = '', priority = 50 })
    vim.fn.sign_define('DapBreakpointRejected',
      { text = dap_ui.DapBreakpointRejected, texthl = 'DapBreakpointRejected', linehl = '', numhl = '', priority = 50 })
    vim.fn.sign_define('DapLogPoint', { text = dap_ui.DapLogPoint, texthl = 'DapLogPoint', linehl = '', numhl = '', priority = 50 })
    vim.fn.sign_define('DapStopped',
      { text = dap_ui.DapStopped, texthl = 'DapBreakpointCondition', linehl = '', numhl = '', priority = 50 })
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close
    -- dap.listeners.after.event_stopped['dapui_config'] = function(session, body)
    --   os.execute '/usr/local/bin/node.exe "C:\\Users\\JFerrara\\Programs\\focus\\focus.js"'
    -- end
    -- dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close
  end,
}
