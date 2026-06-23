-- Leader and Local Leader Keys
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- Special mappings
-- TODO: Move me
vim.api.nvim_set_keymap('n', '<C-w>d', '<Nop>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<C-w><C-d>', '<Nop>', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<C-w>', '<cmd>lua require("harpoon.ui").nav_file(2)<cr>', { noremap = true, silent = true, nowait = true })

-- General Settings
vim.g.have_nerd_font = true
vim.g.copilot_proxy_strict_ssl = false
vim.g.bufferline_auto_hide = 1
vim.g.markdown_folding = 1

-- Options for 'opt'
vim.opt.foldopen:remove 'search'
vim.opt.conceallevel = 2
vim.opt.cmdheight = 0
vim.opt.lazyredraw = true
vim.opt.wrap = false
vim.opt.breakindent = true
vim.opt.smartcase = true
vim.opt.signcolumn = 'yes'
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.list = true
vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }
vim.opt.inccommand = 'split'
vim.opt.hlsearch = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.hidden = true
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.termguicolors = true
vim.opt.spell = false
vim.opt.title = true
vim.opt.ignorecase = true
vim.opt.scrolloff = 30
vim.opt.sidescrolloff = 30
vim.opt.confirm = true
vim.opt.exrc = true
vim.opt.backup = false
vim.opt.autoindent = true
vim.opt.softtabstop = -1
vim.opt.textwidth = 80
vim.opt.incsearch = true
vim.opt.cursorline = false
vim.opt.swapfile = false
vim.opt.ruler = false
vim.opt.autoread = true
vim.opt.showmode = false
vim.opt.fixendofline = false
vim.opt.startofline = false
vim.opt.shiftround = true
vim.opt.backspace = 'indent,eol,start'
vim.opt.backupdir = '~/.local/share/nvim/backup//'
vim.opt.joinspaces = false
vim.opt.wildmode = 'longest:full,full'
vim.opt.mouse = 'a'
vim.opt.undofile = true
vim.opt.smoothscroll = true

vim.o.fillchars = "fold: ";
-- vim.o.foldmethod = "expr";
-- vim.o.foldexpr = "v:lua.vim.treesitter.foldexpr()";
vim.opt.foldcolumn = '0'
vim.opt.foldlevel = 99
vim.opt.foldnestmax = 1
vim.o.foldenable = true

-- TODO: Move to separate file
vim.opt.laststatus = vim.opt.clipboard:append 'unnamedplus' -- use system clipboard as default register

-- WSL2 clipboard via win32yank (requires win32yank.exe in PATH or /mnt/c/ path)
vim.g.clipboard = {
  name = 'win32yank-wsl',
  copy = {
    ['+'] = { '/home/jferrara/.local/bin/win32yank.exe', '-i', '--crlf' },
    ['*'] = { '/home/jferrara/.local/bin/win32yank.exe', '-i', '--crlf' },
  },
  paste = {
    ['+'] = { '/home/jferrara/.local/bin/win32yank.exe', '-o', '--lf' },
    ['*'] = { '/home/jferrara/.local/bin/win32yank.exe', '-o', '--lf' },
  },
  cache_enabled = 1,
}

-- LineNr jumplist mappings for 'k' and 'j'
vim.api.nvim_command [[nnoremap <expr> k (v:count > 1 ? "m'" . v:count : '') . 'k']]
-- Check if Neovim was launched with the +terminal argument
local argv = vim.v.argv or {}
local function launched_with_terminal()
  for _, arg in ipairs(argv) do
    if arg == '+terminal' then
      return true
    end
  end
  return false
end

_G.NVIM_TERMINAL_ONLY = launched_with_terminal()

require 'loaders.lazy'
require 'loaders.mappings'
require 'autocommands'
require 'highlights'

local specs = { { import = 'terminal_plugins' } }
if not _G.NVIM_TERMINAL_ONLY then 
  table.insert(specs, { import = 'plugins' })
end

require('lazy').setup({
  spec = specs,
  performance = {
    cache = { enabled = true },
    reset_packpath = true,
    rtp = {
      disabled_plugins = {
        "2html_plugin",
        "bugreport",
        "compiler",
        "ftplugin",
        "getscript",
        "getscriptPlugin",
        "gzip",
        "logipat",
        "matchit",
        "netrw",
        "netrwFileHandlers",
        "netrwPlugin",
        "netrwSettings",
        "optwin",
        "rplugin",
        "rrhelper",
        "spellfile_plugin",
        "synmenu",
        "syntax",
        "tar",
        "tarPlugin",
        "tohtml",
        "tutor",
        "vimball",
        "vimballPlugin",
        -- "zip",
        -- "zipPlugin",
        "man",
        "matchparen",
        "osc52",
        "shada",
        "spellfile",
      },
    },
  },
}, require('ui').lazy_ui)
