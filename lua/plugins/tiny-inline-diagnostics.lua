return {
  'rachartier/tiny-inline-diagnostic.nvim',
  -- enabled = not _G.NVIM_TERMINAL_ONLY,
  event = 'VeryLazy', -- Or `LspAttach`
  priority = 1000, -- needs to be loaded in first
  config = function()
    require('tiny-inline-diagnostic').setup {
      -- Style preset for diagnostic messages
      -- Available options:
      -- "modern", "classic", "minimal", "powerline",
      -- "ghost", "simple", "nonerdfont", "amongus"
      transparent_bg = true, -- Set the background of the diagnostic to transparent
      transparent_cursorline = true, -- Set the background of the cursorline to transparent (only one the first diagnostic)

      options = {
        multilines = {
          enabled = true,
          always_show = true,
        },
      },
      severity = {
        vim.diagnostic.severity.ERROR,
        vim.diagnostic.severity.WARN,
        vim.diagnostic.severity.INFO,
        vim.diagnostic.severity.HINT,
      },
      disabled_ft = {}, -- List of filetypes to disable the plugin
    }
    vim.diagnostic.config { virtual_text = false } -- Only if needed in your configuration, if you already have native LSP diagnostics
  end,
}
