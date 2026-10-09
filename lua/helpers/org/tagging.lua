-- One-key tagging and priorities for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): a plain letter toggles a tag and an
-- <M-letter> toggles a priority on the entry at point, in an org buffer
-- (the capture buffer included) and in the agenda / TODO view.
--
--   B / F / C          toggle the :bug: / :feat: / :chore: tag
--   <M-a> <M-b> <M-c>  toggle priority A / B / C
--
-- The tags sit on the plain letters the ticket names; the priorities moved
-- to <M-> because B and C are the tag keys, F is the global flash jump, and
-- in the agenda the plain B / F / C (bulk action, follow mode, clock report)
-- are reassigned in `mappings.agenda` to make room. Everything goes through
-- org.tags / org.priority, so an edit carries the full org semantics (tag
-- alignment, OrgTagsChanged / OrgPriorityChanged) and the agenda's
-- save_after_edit writes the source buffer.
--
-- `map` binds the keys in an org buffer; the agenda side registers the same
-- toggles as view actions (`actions`, taken from the specs' `action` field)
-- that `mappings.agenda` in the plugin spec binds by name, the way
-- toggle_done is wired.
local M = {}

--- Tag toggles: tag name, the org/capture key, the agenda action name.
M.tags = {
  { tag = 'bug', key = 'B', action = 'toggle_bug_tag' },
  { tag = 'feat', key = 'F', action = 'toggle_feat_tag' },
  { tag = 'chore', key = 'C', action = 'toggle_chore_tag' },
}

--- Priority toggles: value, the org/capture key, the agenda action name.
M.priorities = {
  { value = 'A', key = '<M-a>', action = 'toggle_priority_a' },
  { value = 'B', key = '<M-b>', action = 'toggle_priority_b' },
  { value = 'C', key = '<M-c>', action = 'toggle_priority_c' },
}

--- Toggle `tag` on the headline at point (or at `target`).
---@param tag string
---@param target? table -- org.Target { bufnr, lnum }
---@return boolean|nil added
function M.toggle_tag(tag, target)
  return require('org.tags').toggle_tag(target, tag)
end

--- Toggle priority `value` ('A'/'B'/'C') on the headline at point (or at
--- `target`): a headline already on it loses its cookie.
---@param value string
---@param target? table -- org.Target { bufnr, lnum }
---@return string|nil priority
function M.toggle_priority(value, target)
  local bufnr, _, hl = require('org.edit').resolve_headline(target)
  if not bufnr then
    return nil
  end
  return require('org.priority').set({ bufnr = bufnr, lnum = hl.line }, hl.priority == value and ' ' or value)
end

--- Bind the tag and priority keys in org buffer `buf` (a capture buffer
--- included), acting on the headline at point. Buffer-local, so the keys
--- land after org.nvim's own mappings and shadow the global F (flash jump)
--- only in org files.
---@param buf integer
function M.map(buf)
  for _, spec in ipairs(M.tags) do
    local tag = spec.tag
    vim.keymap.set('n', spec.key, function()
      M.toggle_tag(tag)
    end, { buffer = buf, desc = 'org: toggle tag :' .. tag .. ':' })
  end
  for _, spec in ipairs(M.priorities) do
    local value = spec.value
    vim.keymap.set('n', spec.key, function()
      M.toggle_priority(value)
    end, { buffer = buf, desc = 'org: toggle priority ' .. value })
  end
end

return M
