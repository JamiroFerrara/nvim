return {
  'folke/snacks.nvim',
  -- enabled = not _G.NVIM_TERMINAL_ONLY,
  event = 'VeryLazy',
  ---@type snacks.Config
  -- priority = 1000, -- removed to avoid startup loading
  opts = {
    -- your configuration comes here
    -- or leave it empty to use the default settings
    -- refer to the configuration section below
    explorer = { enabled = false },
    -- `quickfile` runs on BufReadPost, before `nvim-treesitter` has attached,
    -- and starts a treesitter highlighter of its own: `vim.treesitter.start`
    -- clears `'syntax'` on the buffer. For every other language the fallback
    -- (`vim.bo.syntax = ft` when the parser is missing) is unnecessary, but
    -- `org` is different -- its highlighting is org.nvim's generated vim
    -- syntax (queries/org/highlights.scm is empty), so clearing `'syntax'`
    -- before nvim-treesitter's FileType attach re-enables it leaves the buffer
    -- flat. Excluding `org` keeps the early redraw on vim syntax, which is
    -- what the buffer renders with anyway.
    quickfile = { enabled = true, exclude = { 'latex', 'org' } },
    bigfile = { enabled = true },
    indent = { enabled = true },
    input = { enabled = true },
    notifier = { enabled = true },
  },
}
