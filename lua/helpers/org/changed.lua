-- "Last changed" column of the TODO views (org.nvim), wired in
-- lua/terminal_plugins/org.nvim.lua: the `todo` kind's `prefix_format` ends in
-- a `%(lua expression)` element calling M.label(hl), so every entry line opens
-- with when its entry last changed. The same module's M.setup() registers the
-- `changed-up` / `changed-down` sorting strategies on org.agenda.items, which
-- order a list by that date (the group view's per-state sections).
--
-- org stores no per-headline modification time, so the newest timestamp of the
-- entry stands in for it -- and in this vault the entry's own markers are
-- exactly those: a note/capture rule header is an inactive timestamp, a state
-- change is the CLOSED planning timestamp, a date edited from a view is an
-- active one. M.label takes the maximum of all of them. Only CLOSED is read
-- from the planning line: a SCHEDULED/DEADLINE is a plan, not a change, and a
-- future one must not win the column. An entry that carries no timestamp
-- at all renders as a blank column (the format's `%-13(...)` keeps the field,
-- so the entry's keyword still lands where the dated entries' ones do).
--
-- Recent dates read relative -- today, yest, "3d ago" -- the day's time
-- appended where the timestamp has one; past a week they are a plain "9 Oct",
-- with the year once it is not this one.
--
-- The same date is an org.nvim sorting strategy, `changed-up` /
-- `changed-down`, registered by M.setup(): the group view (`2` in
-- lua/terminal_plugins/org.nvim.lua) orders each of its per-state sections by
-- it, so the column and the list agree on what "recent" means. An entry with
-- no timestamp at all sinks below the dated ones, whichever direction the
-- list runs.
local M = {}

local date = require 'org.date'

--- Newest timestamp of an entry, or nil when it carries none. Title
--- timestamps, CLOSED and the timestamps of the entry's own section (notes,
--- clocks, ranges) count; the planning line is skipped so its
--- SCHEDULED/DEADLINE do not.
---@param hl org.Headline|nil
---@return org.Date|nil
function M.latest(hl)
  if not hl then
    return nil
  end
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
  local d = M.latest(hl)
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

--- The `changed-up` / `changed-down` comparators (org-entries-lessp: -1 puts
--- its first argument first, 1 its second, false leaves the pair to the next
--- strategy). `down` is not the other's reversal: an undated entry sinks --
--- is ordered after a dated one -- whichever direction the list runs, and a
--- plain reversal would flip that with the dates (an `up` rule that puts the
--- undated first would put them last in a `down` list).
---@param older_first boolean
---@param a org.AgendaItem
---@param b org.AgendaItem
local function changed_cmp(older_first, a, b)
  local da, db = M.latest(a.headline), M.latest(b.headline)
  if da == nil then
    return db == nil and false or 1
  elseif db == nil then
    return -1
  end
  local ma, mb = da:minutes(), db:minutes()
  if ma == mb then
    return false
  end
  local r = ma < mb and -1 or 1
  return older_first and r or -r
end

--- Register the two strategies on org.agenda.items (they are looked up by
--- name, so the plugin's own validation accepts them), once it loads -- the
--- module defines the strategy table, and requiring it here would load the
--- whole agenda at startup.
function M.setup()
  require('org.lazy').on_load('org.agenda.items', 'changed_strategies', function(items)
    items.strategies['changed-up'] = function(a, b)
      return changed_cmp(true, a, b)
    end
    items.strategies['changed-down'] = function(a, b)
      return changed_cmp(false, a, b)
    end
  end)
end

return M
