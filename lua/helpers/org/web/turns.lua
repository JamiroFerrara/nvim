-- The dated turns of an entry, drawn as a date in the browser views
-- (helpers/org/web). A note, a capture and an agent's answer each open with a
-- header line -- `[2026-10-28 Wed 20:03] -----…`, the agent's carrying 🤖 in
-- front (helpers/org/notes.lua) -- and org's HTML export writes that line as
-- ordinary paragraph text: the bracketed timestamp, then the dash run, whose
-- trailing dashes Emacs' export turns into an en and an em dash. The page
-- then shows the source of the header instead of the turn it opens.
--
-- This rewrites it into what the line means in the editor
-- (helpers/org/decorations.lua draws it as the timestamp and a rule to the
-- window edge): the date, spelled out, and a rule that reaches the edge of
-- the page, in the agent's colour on an agent block.
local M = {}

local MONTHS = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }

--- `2026-10-28 Wed 20:03` as `Wed 28 Oct 2026, 20:03`, with the same stamp in
--- ISO form for the `<time>` element. A stamp with no time keeps the date
--- alone; one in another shape is returned unchanged, both ways.
---@param ts string
---@return string text, string iso
local function format(ts)
  local y, m, d, dow, time = ts:match '^(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(%a+)%s*(.-)%s*$'
  local month = MONTHS[tonumber(m) or 0]
  if not (y and month) then
    return ts, ts
  end
  local text = ('%s %s %s %s'):format(dow, tonumber(d) or d, month, y)
  local iso = ('%s-%s-%s'):format(y, m, d)
  if time ~= '' then
    text = text .. ', ' .. time
    iso = iso .. 'T' .. time
  end
  return text, iso
end

--- The header a turn gets: the 🤖 of an agent's block (or nothing), the date,
--- and the rule that fills the rest of the row.
---@param icon string
---@param ts string
---@return string
local function turn(icon, ts)
  local text, iso = format(ts)
  local who = icon ~= '' and ('<span class="who">%s</span>'):format(icon) or ''
  return ('<div class="turn%s">%s<time datetime="%s">%s</time><span class="rule"></span></div>'):format(
    icon ~= '' and ' agent' or '',
    who,
    iso,
    text
  )
end

-- a turn's header as the export writes it: an optional icon, the inactive
-- timestamp, and the dash run. Anchored on the paragraph's own line, so a
-- timestamp quoted in the middle of a sentence is left alone.
local HEADER = '([%s\128-\255]*)<span class="timestamp%-wrapper"><span class="timestamp">%[([^%]]+)%]</span></span> %-+[^\n]*\n'

--- Replace every turn header of an exported org document with its date.
---@param html string|nil
---@return string|nil
function M.headers(html)
  if type(html) ~= 'string' or html == '' then
    return html
  end
  -- the header alone in its paragraph (an agent's block, whose text is the
  -- source block below): the paragraph goes, the header stands in its place
  html = html:gsub('<p>\n' .. HEADER .. '</p>', function(icon, ts)
    return turn(icon, ts)
  end)
  -- the header above the note's own text: the paragraph keeps the text, and
  -- the header closes it and opens another
  return (html:gsub('<p>\n' .. HEADER, function(icon, ts)
    return turn(icon, ts) .. '\n<p>'
  end))
end

return M
