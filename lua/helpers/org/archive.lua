-- `archive_all_done` -- `<prefix>D` in org buffers (`<leader>oD`), "archive
-- every child of the headline at point, every top-level tree when not on
-- one, that has no open TODO entries" -- registers its action here instead
-- of the plugin's own (lua/terminal_plugins/org.nvim.lua, in config(),
-- before setup(), like the other overridden actions there).
--
-- org.nvim's archive_all_done() asks before every match it finds ("Move
-- subtree to archive? (no open TODO items) <title>", the per-entry prompt
-- org-archive-all-matches has in Emacs), so one key turns into a confirmation
-- per entry. The rest of this config's archiving already runs without one --
-- `a` / <C-c><C-x><C-a> (archive_default, archive_default_confirm = false)
-- in the buffer and in the agenda. This action joins them: the matches are
-- archived at once, no prompt.
local M = {}

--- The `archive_all_done` action: every matching child archived, no prompt.
function M.archive_all_done()
  return require('org.archive').archive_all_done {
    confirm = function()
      return true
    end,
  }
end

return M
