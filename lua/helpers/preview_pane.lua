--- Paging a preview pane from the list it belongs to.
---
--- `J` / `K` are the global half-page scroll (`<C-d>` / `<C-u>`,
--- lua/mappings.lua). Where a list drives a preview pane beside it -- the org
--- agenda's `L` preview (helpers/org/agenda.lua) and oil's sidebar
--- (terminal_plugins/oil.lua) -- the keys page that pane instead, so the entry
--- being read moves rather than the cursor down the list, which would reload
--- the pane on another entry. Only while the pane has more to show that way: a
--- preview that fits its window leaves the keys the usual scroll of the list.

local M = {}

--- Whether the pane still has somewhere to scroll that way: its viewport must
--- not already show the end it would move toward. A copy of an entry shorter
--- than the pane, or one already scrolled to its last line, has nowhere left
--- to go.
---@param win integer?
---@param down boolean
---@return boolean
function M.can_page(win, down)
  local info = win and vim.api.nvim_win_is_valid(win) and vim.fn.getwininfo(win)[1]
  if not info then
    return false
  end
  if down then
    return info.botline < vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
  end
  return info.topline > 1
end

--- The scroll `key` carries, run in the pane's own window so the pane's cursor
--- and scrolloff rules apply and the list is left alone. When the pane has
--- nothing more to show that way it is the usual scroll of the current window.
---@param win integer? the pane; nil when there is none
---@param key string `<C-d>` (`\6`) or `<C-u>` (`\21`)
---@param down boolean
function M.page(win, key, down)
  local arg = (vim.v.count > 0 and tostring(vim.v.count) or '') .. key
  if M.can_page(win, down) then
    vim.api.nvim_win_call(win, function()
      vim.cmd.normal { args = { arg }, bang = true }
    end)
    return
  end
  vim.cmd.normal { args = { arg }, bang = true }
end

return M
