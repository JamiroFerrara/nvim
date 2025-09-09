---
id: TODO
aliases: []
tags: []
---
# TODO

# important
- [x] Block versions for mason + lspconfi
- [>] ctrl+delete remove full word in nvim
- [>] ctrl+delete remove full word in term
- [>] When running lazygit do the tmux trick like nvim
- [>] treesitter has gotten slower for some reason -> lazy loading
- [ ] Obsidian.nvim has a ripgrep bug -> Command 'rg' with args '{ "--no-config", "--type=md", "--json", "--fixed-strings", "--ignore-case", "-m=1", "-e", "as", "/home/jferrara" }' exited with non-zero code 2. See logs for stderr.
- [ ] Git log + file search from the log
- [ ] Dap broken for React 
- [ ] Folding ffs
- [ ] Copilot is off 
- [ ] viq does not allways work 
- [ ] dap seems to not work from any file (c#)? 
- [ ] Error executing vim.schedule lua callback: ...lazy/nvim-dap-virtual-text/lua/nvim-dap-virtual-text.lua:208: bad argument #1 to 'pairs' (table expected, got nil)
- [ ] typescript lsp for javascript is definately broken, auto imports do not work etc
- [ ] %s/\r//g  -> implement me (CRLF line endings)
- [ ] lsp is slow:
	- [ ] typescript
	- [ ] csharp large projects
- [ ] Firefox debugging 
- [ ] Harpoon directly from terminal 
- [ ] Close zen with alt+w 

#### Plugins
- [ ] junegunn/vim-easy-align
- [ ] ysmb-wtsg/in-and-out.nvim
- [ ] nguyenvukhang/nvim-toggler

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
