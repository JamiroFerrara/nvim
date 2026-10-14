-- A state change refused because the entry still has unfinished children
-- opens the entry's tree, so the child that blocks it comes on screen
-- instead of staying hidden behind a `… (N)`.
--
-- The rule itself is org.nvim's `enforce_todo_dependencies` (on in
-- lua/terminal_plugins/org.nvim.lua): an entry cannot be marked DONE while
-- its children are unfinished, and the change returns with a warning instead
-- of happening. This file is the other half: the refused `D` / `N` /
-- <C-c><C-t> also opens the tree at point the way <Tab> / `l` do -- the
-- view's node in a TODO view (helpers/org/tree.lua), the buffer's own fold
-- (org-fold-show-children) in an org buffer. The children of the blocked
-- entry are usually not on screen: a TODO nested under another TODO is a
-- subtask the view keeps folded under its ancestor (helpers/org/tree.lua).
--
-- The hook wraps org.todo.change_state (org.lazy.on_load, so the wrapper is
-- in place before anything else requires the module), which every path that
-- changes a state goes through: the agenda's `D`
-- (helpers/org/agenda.lua), the plugin's own todo keys, the bulk actions,
-- the checkbox/archive flows (helpers/org/cookies.lua). `force` (C-u C-u
-- C-u <C-c><C-t>) changes the state anyway and opens nothing.
local M = {}

--- The entry a refused change was about, resolved the way change_state
--- resolves its own target.
---@param target? table -- org.Target { bufnr, lnum }
---@return integer|nil bufnr
---@return table|nil hl -- org.Headline
local function resolve(target)
  local ok, edit = pcall(require, 'org.edit')
  if not ok then
    return nil
  end
  local resolved, bufnr, _, hl = pcall(edit.resolve_headline, target)
  if not resolved or not bufnr then
    return nil
  end
  return bufnr, hl
end

--- Open the tree of the entry the change was about. In a TODO view the
--- entry is a line of the view and its node carries the children; in the
--- entry's own buffer, the cursor sits on the headline and its folds are
--- the buffer's.
---@param bufnr integer
---@param hl table -- org.Headline
local function reveal(bufnr, hl)
  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  if vim.bo[buf].filetype == 'orgagenda' then
    require('helpers.org.tree').reveal(buf, lnum, hl)
  elseif buf == bufnr and vim.bo[buf].filetype == 'org' and lnum == hl.line then
    pcall(function()
      require('org.fold').show_children()
    end)
  end
end

function M.setup()
  require('org.lazy').on_load('org.todo', 'reveal_blocked', function(todo)
    local change_state = todo.change_state
    todo.change_state = function(target, new, opts)
      local res = change_state(target, new, opts)
      if res == nil then
        local bufnr, hl = resolve(target)
        if bufnr and hl and hl:has_undone_children() then
          reveal(bufnr, hl)
        end
      end
      return res
    end
  end)
end

return M
