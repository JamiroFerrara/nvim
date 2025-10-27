---
id: TODO
aliases: []
tags: []
---

## Languages
### Markdown
- [ ] Better folding keybind ergonomics 
- [ ] Auto heading folding
- [ ] Fix markdown heading highlighs
- [ ] Instant markdown heading checkbox add
- [ ] Follow markdown url links with brave
- [ ] Paste image in markdown
- [ ] Cicle through less checkbox states
- [ ] Search markdown headings with marksman
- [ ] Jump between markdown headings in lazyvim
- [ ] change pink highlight

### Csharp
- [ ] Replace Omnisharp with Roslyn LSP 
- [ ] csharp large projects slow 

## Plugins
### Plugins New
- [x] junegunn/vim-easy-align 
- [ ] ysmb-wtsg/in-and-out.nvim 
- [ ] Markdown preview
- [ ] https://github.com/lfilho/note2cal.nvim

### Plugins Edit
- [ ] himalaya setup using oAuth2.0 -> https://docs.rs/crate/himalaya/latest 
- [ ] bigger dadbod results window (half screen?) 
- [ ] Obsidian checkboxes aren't allways loading 
- [ ] typescript slow and kinda not working 
- [ ] Flat list todo trouble 
- [ ] Replace obsidian with marksman:
	- [ ] Heading search
- [ ] Copilot is off 
- [ ] Folding ffs -> nvim-origami + upgrade to 11 
- [ ] When running lazygit do the tmux trick like nvim 

## General
### Folds
- [ ] Fix csharp folding 

### Highlights
- [ ] Flash highlight fixes 
- [ ] Fix the lspserver loading black highlight 

### DAP 
- [ ] Buffer completion from debug watch window using cmp 
- [ ] dap seems to not work from any file (c#)? 
- [ ] Error executing vim.sc lua callback: ...lazy/nvim-dap-virtual-text/lua/nvim-dap-virtual-text.lua:208: bad argument #1 to 'pairs' (table expected, got nil) 

### Keybinds
- [ ] viq does not allways work 
- [ ] go back and fourth between file 
- [ ] %s///g  -> implement me (CRLF line endings) 
- [ ] ctrl+delete remove full word in nvim 
- [ ] ctrl+delete remove full word in term
- [ ] focus url bar in brave 
- [ ] Git log + file search from the log 
- [ ] Delete last word
- [ ] git push with insta commit keybind  
- [ ] vault autosync

### Terminal
- [ ] Currently, when running nvim from terminal the initial terminal instance dies, but it should restore if term instance is open 
- [ ] When in terminal ctrl+c must send the char to terminal 
- [ ] Better zsh completion 
- [ ] Harpoon directly from terminal (abstact the copy mechanism) 
- [ ] remove scrollback on clear (terminal) 
- [ ] On terminal enter auto insert mode (and re-enter) 
- [ ] Edit long command in terminal -> [h.misc edit command in terminal](https://www.youtube.com/watch?v=OKuUoZaPiwEk)
- [ ] Paste without windows return chars
- [ ] Disable terminal blinking
- [ ] Delete word

### Tmux
- [ ] Make tmux look nicer [h.misc video](https://www.youtube.com/watch?v=6Jgl5wphD00&t=4s)

### Moonlander
- [ ] j+v should bring me to nvim config automatically
- [ ] Add fucking tilde
- [ ] k layer does not seem to be mapped to anything

### Yml scripts
- [ ] Fix zsh yaml script text glitch 

### Manual Patches
->/home/jferrara/.local/share/nvim/lazy/typescript-tools.nvim/lua/typescript-tools/protocol/module_mapper.lua line 41
->/home/jferrara/.local/share/nvim/lazy/obsidian.nvim/lua/obsidian/util.lua line 775
->/home/jferrara/.local/share/nvim/lazy/snacks.nvim/lua/snacks/picker/config/layouts.lua -> removed borders from ivy_split + vscode
