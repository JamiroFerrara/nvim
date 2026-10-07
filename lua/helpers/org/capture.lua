-- Capture-task destination for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua). The Task template asks where the entry
-- goes before the note is typed, and stores it there directly, instead of
-- dropping it in refile.org and refiling it again. The list is flat: the
-- level-1 headlines of the project files (the projects), no stepping through
-- the outline path, no whole-file entries. `pick` memoizes the choice so the
-- template's `target` and `headline` read it and the picker runs once per
-- capture. Cancelling the picker aborts the capture (utils.abort), so nothing
-- lands in the default notes file.
local M = {}

local dest

--- Ask for the destination project headline. Returns the memoized
--- `{ file, title }` (nil when the pick was cancelled or there was nothing
--- to offer).
function M.pick()
  local utils = require 'org.utils'
  dest = nil
  local targets = require('org.refile').targets {
    targets = { { files = '~/org/projects/*.org', max_level = 1 } },
    bufnr = vim.api.nvim_get_current_buf(),
  }
  local headlines = {}
  for _, t in ipairs(targets) do
    -- whole-file targets carry no line number; keep headlines only
    if t.lnum then
      headlines[#headlines + 1] = t
    end
  end
  if #headlines == 0 then
    utils.warn 'capture: no level-1 headline in ~/org/projects/*.org'
    return nil
  end
  local choice = utils.select(headlines, {
    prompt = 'Task to',
    kind = 'org_capture_target',
    format_item = function(t)
      return string.format('%s -> %s', vim.fn.fnamemodify(t.filename, ':t'), t.olp[#t.olp])
    end,
  })
  if choice then
    dest = { file = choice.filename, title = choice.olp[#choice.olp] }
  end
  return dest
end

--- Template `target`: pick the destination, aborting the capture on cancel.
function M.target()
  if not M.pick() then
    require('org.utils').abort()
  end
  return dest and dest.file
end

--- Template `headline`: the title of the destination picked by `target`.
function M.headline()
  return dest and dest.title
end

return M
