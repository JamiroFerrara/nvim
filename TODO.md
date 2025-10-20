---
id: TODO
aliases: []
tags: []
---
# TODO
- [ ] ctrl+delete remove full word in nvim
- [ ] ctrl+delete remove full word in term
- [>] When running lazygit do the tmux trick like nvim
- [>] treesitter has gotten slower for some reason -> lazy loading
- [ ] Git log + file search from the log
- [ ] Folding ffs -> nvim-origami + upgrade to 11
- [ ] Markdown header folding -> https://linkarzu.com/posts/neovim/markdown-setup-2024/#marksman
- [ ] Obsidian checkboxes aren't allways loading
- [ ] Replace obsidian with marksman?
- [ ] Copilot is off 
- [ ] viq does not allways work 
- [ ] go back and fourth between file
- [ ] bigger dadbod results window (half screen?)
- [ ] focus url bar in brave
- [ ] fzf + fzy keybinds
- [ ] himalaya setup using oAuth2.0 -> https://docs.rs/crate/himalaya/latest
- [ ] Flat list todo trouble
[ ] %s/\r//g  -> implement me (CRLF line endings)
- [ ] Fix bold colors on highlight
- [ ] terminal:
	- [ ] Harpoon directly from terminal (abstact the copy mechanism)
	- [ ] remove scrollback on clear (terminal)
	- [ ] On terminal enter auto insert mode (and re-enter)
- [ ] lsp:
	- [ ] typescript slow and kinda not working
	- [ ] csharp large projects slow
- [ ] dap:
	- [ ] dap seems to not work from any file (c#)? 
	- [ ] Error executing vim.sc lua callback: ...lazy/nvim-dap-virtual-text/lua/nvim-dap-virtual-text.lua:208: bad argument #1 to 'pairs' (table expected, got nil)
	- [ ] Buffer completion from debug watch window using cmp

#### Plugins
- [ ] junegunn/vim-easy-align
- [ ] ysmb-wtsg/in-and-out.nvim

#### Terminal
- [>] Currently, when running nvim from terminal the initial terminal instance dies, but it should restore if term instance is open
- [ ] When in terminal ctrl+c must send the char to terminal 
- [ ] Better zsh completion

#### Csharp
- [ ] Replace Omnisharp with Roslyn LSP 

#### Markdown
- [ ] bold fonts for markdown
- [ ] italic fonts for markdown 
- [?] Replace Obsidian with Marksman

#### Highlights
- [ ] Flash highlight fixes
- [ ] Fix the lspserver loading black highlight

#### Manual Patches
->/home/jferrara/.local/share/nvim/lazy/typescript-tools.nvim/lua/typescript-tools/protocol/module_mapper.lua line 41
->/home/jferrara/.local/share/nvim/lazy/obsidian.nvim/lua/obsidian/util.lua line 775
->/home/jferrara/.local/share/nvim/lazy/snacks.nvim/lua/snacks/picker/config/layouts.lua -> removed borders from ivy_split + vscode
