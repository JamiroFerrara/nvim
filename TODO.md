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
- [ ] Pragrmatic debugging for csharp 
- [ ] On terminal enter auto insert mode (and re-enter)

### Zen + Trydactyl - https://wiki.csgalileo.org/tips/tridactyl - https://raw.githubusercontent.com/arimasou16/dotfiles/master/.tridactylrc
- [ ] Configuration file 
- [ ] Search jira
- [ ] Improve searching
- [ ] tabdetach with alt+s
- [ ] intall native messenger -> powershell -ExecutionPolicy Bypass -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12;(New-Object System.Net.WebClient).DownloadFile('https://raw.githubusercontent.com/tridactyl/native_messenger/master/installers/windows.ps1', '%TEMP%/tridactyl_installnative.ps1');& '%TEMP%/tridactyl_installnative.ps1' -Tag 1.24.4;Remove-Item '%TEMP%/tridactyl_installnative.ps1'"
- [ ] run commands in new tabs also (--mode=browser)
- [ ] use https://git.frogeye.fr/geoffrey/dotfiles/src/branch/prenix/config/tridactyl/tridactylrc
- [ ] Map C-p in ex mode to traverse history 
- [ ] Trydactyl tabs is overriding normal tabs? 
- [ ] Insta tab switch when browsing buffers 
- [ ] Fix visual themes  
- [ ] Ctrl+shft+t for transparency hides restore tabs 
- [ ] Tabs change direction? 

##### Configuration opts
set completions.History.autoselect true
set tabsort mru
set hintfiltermode simple
set hintnames short
bind --mode=normal b fillcmdline taball
bind --mode=normal <C-s> composite tabdetach
bind --mode=normal <A-s> composite tabdetach
bind --mode=normal W composite tabdetach
bind --mode=ex <C-j> ex.next_completion
bind --mode=ex <C-k> ex.prev_completion

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
