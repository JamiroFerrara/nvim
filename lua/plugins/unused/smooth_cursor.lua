return {
  'gen740/SmoothCursor.nvim',
  -- enabled = not _G.NVIM_TERMINAL_ONLY,
  enabled = false,
  event = 'VeryLazy',
  opts = {
    autostart = true,
    cursor = '', -- cursor shape (need nerd font)
    texthl = 'SmoothCursor', -- highlight group, default is { bg = nil, fg = "#FFD400" }
    linehl = nil, -- highlight sub-cursor line like 'cursorline', "CursorLine" recommended
    type = 'default', -- define cursor movement calculate function, "default" or "exp" (exponential).
    fancy = {
      enable = true, -- enable fancy mode
      head = { cursor = '', texthl = '@field', linehl = nil },
      body = {
        { cursor = 'ﱲ', texthl = '@punctuation.special' },
        { cursor = '', texthl = '@field' },
        { cursor = '●', texthl = '@field' },
        { cursor = '●', texthl = '@field' },
        { cursor = '•', texthl = '@field' },
        { cursor = '.', texthl = '@field' },
        { cursor = '.', texthl = '@field' },
      },
      tail = { cursor = nil, texthl = 'SmoothCursor' },
    },
    flyin_effect = nil, -- "bottom" or "top"
    speed = 20, -- max is 100 to stick to your current position
    intervals = 20, -- tick interval
    priority = 10, -- set marker priority
    timeout = 3000, -- timout for animation
    threshold = 3, -- animate if threshold lines jump
    disable_float_win = false, -- disable on float window
    enabled_filetypes = nil, -- example: { "lua", "vim" }
    disabled_filetypes = nil, -- this option will be skipped if enabled_filetypes is set. example: { "TelescopePrompt", "NvimTree" }
  },
}
