return { -- Highlight, edit, and navigate code
  'nvim-treesitter/nvim-treesitter',
  -- enabled = not _G.NVIM_TERMINAL_ONLY,
  -- `main` is the 2025 rewrite: no `nvim-treesitter.configs`, no `define_modules`
  -- (breaks playground + the `highlight`/`indent`/`ensure_installed` opts below).
  -- `master` is the frozen legacy-API branch kept for nvim 0.11.
  branch = 'master',
  event = { 'BufReadPost', 'BufNewFile' },
  build = ':TSUpdate',
  dependencies = {
    'nvim-treesitter/playground',
    'nvim-treesitter/nvim-treesitter-textobjects',
  },
  -- lazy = 'BufReadPre',
  opts = {
    ensure_installed = { 'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'vim', 'vimdoc', 'c_sharp', 'php', 'javascript', 'typescript' },
    -- `org` is neither installed nor updated automatically: the config
    -- function below installs it itself, once, and keeps `auto_install` off
    -- it. Filetype detection fires `FileType` twice for a buffer opened at
    -- startup, and each firing starts an `auto_install`, so the two would
    -- race each other over the one `tree-sitter-org` clone in the data
    -- directory.
    ignore_install = { 'org' },
    -- Autoinstall languages that are not installed
    auto_install = true,
    highlight = {
      enable = true,
      -- Some languages depend on vim's regex highlighting system (such as Ruby) for indent rules.
      --  If you are experiencing weird indenting issues, add the language to
      --  the list of additional_vim_regex_highlighting and disabled languages for indent.
      -- `org` is only here for the injected markdown: starting the highlighter
      -- turns off vim syntax for the buffer, which would take org.nvim's own
      -- highlighting (headlines, keywords, src blocks) with it.
      additional_vim_regex_highlighting = { 'ruby', 'org' },
    },
    indent = { enable = true, disable = { 'ruby' } },
  },
  config = function(_, opts)
    -- [[ Configure Treesitter ]] See `:help nvim-treesitter`

    vim.treesitter.language.register('c_sharp', 'csharp')

    -- Prefer git instead of curl in order to improve connectivity in some environments
    require('nvim-treesitter.install').prefer_git = true

    -- Upstream nvim-treesitter has no `org` parser: the grammar is registered
    -- here. It is only used for the markdown injected into
    -- `#+begin_src markdown` blocks (queries/org/injections.scm); the rest of
    -- the buffer stays with org.nvim's syntax.
    local parsers = require 'nvim-treesitter.parsers'
    parsers.list.org = {
      install_info = {
        url = 'https://github.com/nvim-orgmode/tree-sitter-org',
        files = { 'src/parser.c', 'src/scanner.c' },
        -- the installer would otherwise check out `master`, which this
        -- grammar (default branch `main`) does not have
        branch = 'main',
      },
      filetype = 'org',
      maintainers = { '@jferrara' },
    }

    -- Build it here and not through `auto_install` (`ignore_install` above):
    -- filetype detection fires `FileType` twice for a buffer opened at
    -- startup and each firing would start its own install, the two racing
    -- over the one `tree-sitter-org` clone in the data directory (the second
    -- clone fails on the directory the first just made). One install is
    -- enough: it reattaches the highlighter when it finishes, so the blocks
    -- render without reopening the file.
    if not parsers.has_parser 'org' then
      require('nvim-treesitter.install').ensure_installed { 'org' }
    end

    ---@diagnostic disable-next-line: missing-fields
    require('nvim-treesitter.configs').setup(opts)

    -- There are additional nvim-treesitter modules that you can use to interact
    -- with nvim-treesitter. You should go explore a few and see what interests you:
    --
    --    - Incremental selection: Included, see `:help nvim-treesitter-incremental-selection-mod`
    --    - Show your current context: https://github.com/nvim-treesitter/nvim-treesitter-context
    --    - Treesitter + textobjects: https://github.com/nvim-treesitter/nvim-treesitter-textobjects
  end,
}
