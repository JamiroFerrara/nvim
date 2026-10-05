--- Focusing a terminal always drops you into insert mode — except when the
--- buffer is reached through a jumplist jump (`<C-o>` / `<C-i>`), where you want
--- to land in normal mode and keep navigating.
local M = {}

M.skip_next = false

--- Execute a jumplist jump. Any terminal buffer entered by the jump stays in
--- normal mode instead of auto-entering insert.
---@param keys string Key sequence that starts the jump, e.g. '<C-o>'.
function M.jump(keys)
  M.skip_next = true
  -- 'nx': run the sequence synchronously so BufEnter fires (and is suppressed)
  -- before the flag is cleared again.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'nx', false)
  M.skip_next = false
end

--- Consume the skip flag. Returns whether a focused terminal should insert.
---@return boolean
function M.should_insert()
  if M.skip_next then
    M.skip_next = false
    return false
  end
  return true
end

return M
