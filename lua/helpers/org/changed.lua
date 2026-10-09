-- "Last changed" column of the TODO views (org.nvim), wired in
-- lua/terminal_plugins/org.nvim.lua: the `todo` kind's `prefix_format` ends in
-- a `%(lua expression)` element calling M.label(hl), so every entry line opens
-- with when its entry last changed.
--
-- org stores no per-headline modification time, so the newest timestamp of the
-- entry stands in for it -- and in this vault the entry's own markers are
-- exactly those: a note/capture rule header is an inactive timestamp, a state
-- change is the CLOSED planning timestamp, a date edited from a view is an
-- active one. M.label takes the maximum of all of them. Only CLOSED is read
-- from the planning line: a SCHEDULED/DEADLINE is a plan, not a change, and a
-- future one must not win the column. An entry that carries no timestamp at
-- all renders as nothing (the `%?` in the format drops the field).
--
-- Recent dates read relative -- today, yest, "3d ago" -- the day's time
-- appended where the timestamp has one; past a week they are a plain "9 Oct",
-- with the year once it is not this one.
local M = {}

local date = require 'org.date'

--- Newest timestamp of an entry, or nil. Title timestamps, CLOSED and the
--- timestamps of the entry's own section (notes, clocks, ranges) count; the
--- planning line is skipped so its SCHEDULED/DEADLINE do not.
---@param hl org.Headline
---@return org.Date|nil
local function latest(hl)
  local best
  local function consider(d)
    if d and (not best or d:minutes() > best:minutes()) then
      best = d
    end
  end
  for _, item in ipairs(date.parse_all(hl.title or '')) do
    consider(item.date)
  end
  consider(hl.planning and hl.planning.closed)
  for _, line in ipairs(hl:body_lines()) do
    for _, item in ipairs(date.parse_all(line)) do
      consider(item.date)
    end
  end
  return best
end

--- The "last changed" text of the entry, or "" when it carries no date.
---@param hl org.Headline|nil
---@return string
function M.label(hl)
  if not hl then
    return ''
  end
  local d = latest(hl)
  if not d then
    return ''
  end
  local ago = date.today_days() - d:days() -- positive = in the past
  local hm = d.hour and string.format('%02d:%02d', d.hour, d.min or 0) or nil
  if ago == 0 then
    return hm and ('today ' .. hm) or 'today'
  elseif ago == 1 then
    return hm and ('yest ' .. hm) or 'yest'
  elseif ago > 1 and ago < 7 then
    return ago .. 'd ago'
  elseif d.year == date.today().year then
    return d:strftime '%-d %b'
  end
  return d:strftime '%-d %b %Y'
end

return M
