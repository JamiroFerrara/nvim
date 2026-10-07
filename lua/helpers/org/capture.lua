-- Capture-task destination for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua). The Task template asks where the entry
-- goes before the note is typed, and stores it there directly, instead of
-- dropping it in refile.org and refiling it again.
--
-- The cwd decides first: helpers/org/project.lua resolves the working
-- directory to its project (a `#+PROJECT_DIRS:` / `:PROJECT_DIRS:` claim,
-- else the nearest `.git` root) and the capture goes there, with no prompt.
-- Only when the cwd names no project does the picker run: the flat list of
-- level-1 headlines of the project files, no outline path, no whole-file
-- entries.
--
-- The destination is an outline path (`olp`), not a title: a project can be
-- a headline inside a shared file, and a title match would land on the first
-- same-named headline anywhere in it. The template carries `olp` instead of
-- `headline` for that reason.
--
-- This is the write side, so a `.git`-derived project file that does not
-- exist yet is created here (project.ensure) -- looking at a project (`£`,
-- `°`) never creates one, and neither does anything create a headline.
-- `pick` memoizes the choice so the template's `target` and `olp` read it
-- and the resolution runs once per capture. Cancelling the picker aborts the
-- capture (utils.abort), so nothing lands in the default notes file.
local M = {}

local dest

--- Ask for the destination project. Returns the memoized `{ file, olp }`
--- (nil when the pick was cancelled or there was nothing to offer).
function M.pick()
  local utils = require 'org.utils'
  dest = nil
  local project = require 'helpers.org.project'
  local current = project.current()
  if current and project.ensure(current) then
    dest = { file = current.file, olp = project.olp(current) }
    return dest
  end
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
    -- the picker only offers level-1 headlines, so its path ends there
    dest = { file = choice.filename, olp = { choice.olp[#choice.olp] } }
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

--- Template `olp`: the outline path the destination picked by `target` names.
function M.olp()
  return dest and dest.olp
end

return M
