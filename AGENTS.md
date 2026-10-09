# Agent Guidelines for JVIM Neovim Configuration

## Navigation
- Terminal/tmux surface: tmux panes run `nvim +terminal` (`.tmux.conf` `default-command`); terminal-only mode is `init.lua`'s `NVIM_TERMINAL_ONLY`; the `<leader>ai` omp pane is `lua/helpers/org/ai.lua`.

## Build/Lint/Test Commands
- **Format check** (changed files): `stylua --check <files>`; the `.githooks/pre-commit` hook runs this on staged `.lua` files (enable once with `git config core.hooksPath .githooks`)
- **Format fix**: `stylua <files>`
- **No unit tests**: This is a Neovim configuration, not an application with traditional tests

## Code Style Guidelines

### Formatting
- `.stylua.toml` is the source of truth; `stylua` applies it.

### Imports and Dependencies
- Use `require` for module imports
- Lazy loading with `event`, `cmd`, or `ft` specifications in plugin configs
- Dependencies listed explicitly in plugin specs

### Naming Conventions
- Functions: `camelCase` or `snake_case` (mix used, prefer consistency within files)
- Variables: `snake_case` for locals, `UPPER_CASE` for globals
- Plugin files: `snake_case.lua` matching plugin names

### Error Handling
- Standard Lua error patterns
- Use `pcall` for potentially failing operations
- Graceful degradation for optional features

### Plugin Structure
- Plugin configs return table specs for lazy.nvim
- Use `opts` functions for complex configurations
- Separate concerns: config functions, mappings, autocommands

### Best Practices
- Minimal comments - code should be self-documenting
- Use vim.api functions over vim.cmd when possible
- Buffer-local mappings in LSP attach callbacks
- Consistent use of vim.keymap.set over vim.api.nvim_set_keymap</content>
<parameter name="filePath">/home/jferrara/dotfiles/nvim/AGENTS.md