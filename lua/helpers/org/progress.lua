-- Progress column of the TODO views (org.nvim), wired in
-- lua/terminal_plugins/org.nvim.lua: the `todo` kind's `prefix_format` carries
-- a `%(lua expression)` element calling M.label(hl), so the line of a ticket
-- an omp instance is working shows how far the run says it has gone.
--
-- The number is the run's own; nothing here can derive it. Only the agent
-- working the ticket knows how much of it is left, so it keeps the estimate in
-- the headline's `:OMP_PROGRESS:` property -- a bare 0-100 -- and rewrites it
-- as it works (the omp-org-ticket skill: update it at the boundaries of your
-- plan, remove it in the write-back, where the same rule forbids leaving
-- anything else behind). The launcher seeds the key at `0` when it claims the
-- ticket (helpers/org/ai.lua), so the column is up from the run's first
-- moment, and the org-tree watcher (helpers/org/watch.lua) reloads the file
-- and re-renders the view on every write the run makes, so the column moves
-- with it.
--
-- A property is where the number has to live. The title is the user's, and a
-- `[NN%]` written into it would be a statistics cookie: helpers/org/cookies.lua
-- reads any `[n/m]` / `[n%]` on a headline as one, recomputes it from what the
-- entry's checkboxes or child entries actually hold and drops it when there is
-- nothing to count -- which a leaf ticket is -- so a run's own percentage could
-- not survive there. A tag would have to be rewritten into the tag column, and
-- a body line is not on the entry line the view draws. The drawer is the one
-- part of the entry nothing else claims and the view can render.
local M = {}

--- The headline property holding the percentage a run reports. The value is a
--- bare number (`OMP_PROGRESS: 40`), the shape the launcher seeds and the skill
--- asks the run to write.
local PROP = 'OMP_PROGRESS'

--- The progress column of `hl`: its `:OMP_PROGRESS:` value as a percentage
--- (`40%`), or "" when the entry carries none. Only the property's own entry is
--- read (no inheritance: a run reports on its ticket, not on its children). A
--- value that is not a number reads as absent rather than as a misprinted one,
--- and the number is clamped to 0-100 so a stray line cannot widen the column.
---@param hl org.Headline|nil
---@return string
function M.label(hl)
  local raw = hl and hl:get_property(PROP, false)
  local n = tonumber((raw or ''):match '^%s*(%d+)')
  if not n then
    return ''
  end
  return math.min(100, n) .. '%'
end

return M
