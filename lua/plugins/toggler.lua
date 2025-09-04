return {
  'nguyenvukhang/nvim-toggler',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  config = function()
    -- init.lua
    require('nvim-toggler').setup {
      -- your own inverses
      inverses = {
        ['vim'] = 'emacs',
        ['true'] = 'false',
        ['on'] = 'off',
        ['up'] = 'down',
        ['left'] = 'right',
        ['hot'] = 'cold',
        ['day'] = 'night',
        ['light'] = 'dark',
        ['yes'] = 'no',
      },
      -- removes the default <leader>i keymap
      remove_default_keybinds = true,
      remove_default_inverses = true,
      autoselect_longest_match = false,
    }
  end,
}
