-- `archive_all_done` -- `<prefix>D` in org buffers (`<leader>oD`), "archive
-- every child of the headline at point, every top-level tree when not on one,
-- that has no open TODO entries" -- registers its action here instead of the
-- plugin's own (lua/terminal_plugins/org.nvim.lua, in config(), before
-- setup(), like the other overridden actions there), and hands the work to
-- helpers/org/roll.lua.
--
-- Two things were wrong with the plugin's own action for this vault:
--
--   * org.nvim's archive_all_done() asks before every match it finds ("Move
--     subtree to archive? (no open TODO items) <title>", the per-entry prompt
--     org-archive-all-matches has in Emacs), so one key turns into a
--     confirmation per entry. The rest of this config's archiving already runs
--     without one -- `a` / <C-c><C-x><C-a> (archive_default,
--     archive_default_confirm = false) in the buffer and in the agenda. This
--     action joins them: the matches are archived at once, no prompt.
--   * it archives to `<file>.org_archive` beside the board, one file that
--     grows forever (nvim.org_archive reached 155 KB / 2553 lines / 112 agent
--     hand-backs). helpers/org/roll.lua sends each month's closed tickets to
--     ~/org/archive/<client>/<YYYY-MM>.org_archive instead, covers every
--     workstream of the board rather than the one under the cursor, and
--     reports what it moved.
local M = {}

--- The `archive_all_done` action: every finished ticket rolled, no prompt.
function M.archive_all_done()
  return require('helpers.org.roll').roll()
end

return M
