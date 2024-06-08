-- Leader and Local Leader Keys
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- General Settings
vim.g.have_nerd_font = true
vim.g.copilot_proxy_strict_ssl = false
vim.g.bufferline_auto_hide = 1

-- Options for 'opt'
vim.opt.lazyredraw = true
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
vim.opt.clipboard = 'unnamedplus'
vim.opt.laststatus = 2
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
vim.opt.foldmethod = 'syntax'
vim.opt.foldnestmax = 1
vim.opt.foldlevel = 3
vim.opt.foldenable = false

-- Key Mappings
vim.api.nvim_command [[nnoremap <expr> k (v:count > 1 ? "m'" . v:count : '') . 'k']]
vim.api.nvim_command [[nnoremap <expr> j (v:count > 1 ? "m'" . v:count : '') . 'j']]

require 'loaders.lazy'
require 'loaders.mappings'
require 'autocommands'
require 'highlights'
require('lazy').setup({ {
  import = 'plugins',
} }, require('ui').lazy_ui)
