# Agent Guidelines for JVIM Neovim Configuration

## Build/Lint/Test Commands
- **Format check**: `stylua --check .`
- **Format fix**: `stylua .`
- **No unit tests**: This is a Neovim configuration, not an application with traditional tests

## Code Style Guidelines

### Formatting
- Use `stylua` for Lua formatting (configured in `.stylua.toml`)
- 2-space indentation
- Column width: 160 characters
- Unix line endings
- Single quotes preferred for strings
- No parentheses around function calls when possible

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