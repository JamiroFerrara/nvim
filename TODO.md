---
id: TODO
aliases: []
tags: []
---

## Languages
### Org
- [ ] Checkboxes
- [ ] Folding
- [ ] Agenda backspace go back
- [ ] unable to update STIWIE calendar events
- [ ] calendar events with same name don't work
- [ ] tables
- [ ] TODO - DONE state switch
- [ ] Custom TODO keywords + highlights
- [ ] Calendar sync only TODO items
- [ ] Calendar events start folded
- [ ] Unable to go back to agenda from file if entered from there
- [ ] archive (leader<o$>) is a little unergonomic
- [ ] agenda buffer, refresh on enter
- [ ] org captures
- [ ] async gcal sync
- [ ] autocompletion
- [ ] link follow
- [ ] Fold all has 3 modes
- [ ] Fold all has message (make silent)
- [ ] when running org markdown breaks
### Markdown
- [~] Fix markdown heading highlighs:
	- [ ] It's not actually working, only when harpooning to the file directly
- [x] Follow markdown url links with brave
- [ ] markdown smart action sometimes does not work
- [ ] Better folding keybind ergonomics 
- [ ] Auto heading folding
- [ ] Instant markdown heading checkbox add
- [ ] Paste image in markdown
- [ ] Cicle through less checkbox states
- [ ] Search markdown headings with marksman
- [ ] Jump between markdown headings in lazyvim
- [ ] when i press o on markdown header it goes to line beneath
- [ ] Keep the rendering when switching buffers
- [>] Replace obsidian with marksman:
	- [ ] Heading search

### Csharp
- [ ] Replace Omnisharp with Roslyn LSP 
- [ ] csharp large projects slow 

## Plugins
### Plugins New
- [x] junegunn/vim-easy-align 
- [ ] ysmb-wtsg/in-and-out.nvim 
- [ ] Markdown preview
- [ ] tabout
- [ ] treesj
- [ ] https://github.com/lfilho/note2cal.nvim
### Plugins Edit
- [ ] himalaya setup using oAuth2.0 -> https://docs.rs/crate/himalaya/latest 
- [?] bigger dadbod results window (half screen?) 
- [?] typescript slow and kinda not working 
- [ ] Flat list todo trouble 
- [ ] Copilot is off 
- [ ] When running lazygit do the tmux trick like nvim 
- [ ] gcalcli change to stiwiemayday as to see all events

### Chrome Network 
- [ ] Add error state to api list 
- [ ] curl repeat
- [ ] view requesta data
- [ ] parse url ?

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
- [?] ctrl+delete remove full word in nvim 
- [?] ctrl+delete remove full word in term
- [ ] viq does not allways work 
- [~] C-y focus url bar in brave 
- [ ] Git log + file search from the log 
- [ ] Delete last word
- [ ] git push with insta commit keybind  
- [ ] vault autosync
- [ ] alt+enter should spawn terminal if none exists, if not should minimize and or full screen it 
- [ ] alt+h alt+l should conditionally check if there's a pane on left if not should execute the glaze command
- [ ] alt+o in insert mode terminal

### Terminal
- [ ] When in terminal ctrl+c must send the char to terminal 
- [ ] Harpoon directly from terminal (abstact the copy mechanism) 
- [?] remove scrollback on clear (terminal) 
- [?] On terminal enter auto insert mode (and re-enter) 
- [ ] Delete word
- [ ] Lazygit change copy path mapping
- [ ] Lazygit automap to file with nvim
- [ ] xdg-open -> brave
- [ ] fix nvim terminal text cutoff
- [ ] launch nvim terminal applications from terminal

### Moonlander
- [ ] j+v should bring me to nvim config automatically
- [ ] j+c should bring me to tmux calendar + taskwarrior
- [ ] k layer does not seem to be mapped to anything
- [ ] Add fucking tilde

### Taskwarrior
- [ ] Dependent tasks arent showed toghether 
- [ ] Google calendar integration
### Yml scripts
- [ ] Fix zsh yaml script text glitch 

### Manual Package Patches
/home/jferrara/.local/share/nvim/lazy/snacks.nvim/lua/snacks/picker/config/layouts.lua -> removed borders from ivy_split + vscode
/home/jferrara/.local/share/nvim/lazy/nvim-origami/lua/origami/features/foldtext.lua -> comment line 21 and 22
/home/jferrara/.local/share/nvim/lazy/orgmode/lua/orgmode/org/mappings.lua -> removed "Note taken on" string on line 856 

## Optimization
### Terminal Startup
	1. neopostman.nvim 19.16ms
	2. telescope.nvim 16.38ms
	3. lazy.nvim 10.05ms
	4. nvim-treesitter 7.46ms
	5. lualine.nvim 5.05ms
	6. telescope-frecency.nvim 4.94ms
	7. tmux.nvim 3.48ms
	8. playground 3.8ms
	9. term-edit.nvim 2.79ms
	10. nvim-origami 2.08ms
	11. telescope-git-file-history.nvim 1.57ms
	12. snacks.nvim 1.45ms
	13. nvim-treesitter-textobjects 1.47ms
	14. smear-cursor.nvim 1.14ms
	15. flash.nvim 1.04ms
	16. vim-fugitive 1.03ms
	17. nvim-transparent 0.95ms
	18. nui.nvim 0.27ms
	19. zen-mode.nvim 0.25ms
	20. nvim-web-devicons 0.24ms
	21. telescope-ui-select.nvim 0.22ms
	22. telescope-fzf-native.nvim 0.2ms
	23. plenary.nvim 0.3ms
	24. w3m.vim 0.32ms
	25. conform.nvim 0.15ms
	26. impatient.nvim 0.06ms
	- [x] 27. nvim 0.05ms colorscheme catppuccin
