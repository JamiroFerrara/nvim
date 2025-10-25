---
id: TODO
aliases: []
tags: []
---

## Languages
### Csharp 
- [ ] Replace Omnisharp with Roslyn LSP 
- [ ] csharp large projects slow 

### Markdown 
- [ ] Markdown header folding -> https://linkarzu.com/posts/neovim/markdown-setup-2024/#marksman 
- [ ] Markview ?
- [ ] bold fonts for markdown 
- [ ] italic fonts for markdown 


## Plugins
### Plugins New 
- [ ] junegunn/vim-easy-align 
- [ ] ysmb-wtsg/in-and-out.nvim 

### Plugins Edit 
- [ ] himalaya setup using oAuth2.0 -> https://docs.rs/crate/himalaya/latest 
- [ ] bigger dadbod results window (half screen?) 
- [ ] Obsidian checkboxes aren't allways loading 
- [ ] typescript slow and kinda not working 
- [ ] Flat list todo trouble 
- [ ] Replace obsidian with marksman? 
- [ ] Copilot is off 
- [ ] Folding ffs -> nvim-origami + upgrade to 11 
- [ ] When running lazygit do the tmux trick like nvim 

## General
### Highlights 
- [ ] Flash highlight fixes 
- [ ] Fix the lspserver loading black highlight 

### DAP 
- [ ] Buffer completion from debug watch window using cmp 
- [ ] dap seems to not work from any file (c#)? 
- [ ] Error executing vim.sc lua callback: ...lazy/nvim-dap-virtual-text/lua/nvim-dap-virtual-text.lua:208: bad argument #1 to 'pairs' (table expected, got nil) 

### Keybinds 
- [?] viq does not allways work 
- [?] go back and fourth between file 
- [ ] %s///g  -> implement me (CRLF line endings) 
- [ ] ctrl+delete remove full word in nvim 
- [ ] ctrl+delete remove full word in term 
- [ ] focus url bar in brave 
- [ ] Git log + file search from the log 

### Terminal 
- [ ] Currently, when running nvim from terminal the initial terminal instance dies, but it should restore if term instance is open 
- [ ] When in terminal ctrl+c must send the char to terminal 
- [ ] Better zsh completion 
- [ ] Harpoon directly from terminal (abstact the copy mechanism) 
- [ ] remove scrollback on clear (terminal) 
- [ ] On terminal enter auto insert mode (and re-enter) 

### Manual Patches
->/home/jferrara/.local/share/nvim/lazy/typescript-tools.nvim/lua/typescript-tools/protocol/module_mapper.lua line 41
->/home/jferrara/.local/share/nvim/lazy/obsidian.nvim/lua/obsidian/util.lua line 775
->/home/jferrara/.local/share/nvim/lazy/snacks.nvim/lua/snacks/picker/config/layouts.lua -> removed borders from ivy_split + vscode
