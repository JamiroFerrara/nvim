-- A headline of an exported org document, taken apart for the browser views
-- (helpers/org/web). org.nvim's HTML export writes one flat run of markup:
--
--   <h2 id="org…"><span class="section-number-2">2.</span>
--   <span class="todo NEXT">NEXT</span> title <code>[0/2]</code>&nbsp;&nbsp;&nbsp
--   <span class="tag"><span class="nvim">nvim</span></span></h2>
--
-- held together by the three no-break spaces the exporter puts before the
-- tags, and with the statistics cookie drawn as an inline code span. The
-- table of contents carries the same parts with no heading element around
-- them.
--
-- This gives each part a span of its own -- the section number, the state,
-- the title, the cookie and the tags -- and puts a `headline` class on the
-- row, so the stylesheet can lay the parts out as one line: the title taking
-- the width, the tags at the far end, the cookie a quiet counter instead of a
-- code span. A title keeps its own inline markup (a link, a code span, a
-- timestamp); nothing else of the document changes.
local M = {}

local function trim(text)
  return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- The reformatted parts of a headline, from the exporter's own run of them.
---@param inner string
---@return string
local function restructure(inner)
  local out = {}
  local rest = inner

  local number, after = rest:match '^<span class="section%-number%-?%d*">(.-)</span>%s*(.*)$'
  if number then
    out[#out + 1] = '<span class="section-number">' .. number .. '</span>'
    rest = after
  end

  -- the state and the priority, in whichever order the exporter wrote them:
  -- `<span class="todo NEXT">NEXT</span>`, `<span class="priority">[#A]</span>`
  for _ = 1, 2 do
    local classes, label, after = rest:match '^<span class="([^"]*)">([^<]*)</span>%s*(.*)$'
    if classes and (classes:match '^todo' or classes:match '^done') then
      out[#out + 1] = ('<span class="%s">%s</span>'):format(classes, label)
      rest = after
    elseif classes == 'priority' then
      out[#out + 1] = ('<span class="priority">%s</span>'):format(label)
      rest = after
    else
      break
    end
  end

  -- the tags close the heading, after the exporter's no-break spaces (three
  -- entities, the last one unsemicoloned)
  local title, tags = rest:match '^(.-)&nbsp;&nbsp;&nbsp<span class="tag">(.-)</span>%s*$'
  if not tags then
    title = rest
  end
  title = trim(title)
    -- the statistics cookie is set as inline code by the exporter
    :gsub('<code>(%[%d*/%d*%])</code>', '<span class="cookie">%1</span>')
    :gsub('<code>(%[%d+%%%])</code>', '<span class="cookie">%1</span>')
  out[#out + 1] = '<span class="title">' .. title .. '</span>'

  if tags then
    out[#out + 1] = '<span class="tag">' .. (tags:gsub('&nbsp;', '')) .. '</span>'
  end
  return table.concat(out)
end

M.restructure = restructure

--- Give every heading of an exported document its parts, and the same to the
--- entries of its table of contents.
---@param html string|nil
---@return string|nil
function M.html(html)
  if type(html) ~= 'string' or html == '' then
    return html
  end
  for level = 1, 6 do
    html = html:gsub('(<h' .. level .. ' id="[^"]*")([^>]*)>(.-)</h' .. level .. '>', function(open, attrs, inner)
      -- a headline class of the document's own is kept, beside this one
      local extra = attrs:match ' class="([^"]*)"'
      attrs = attrs:gsub('%s*class="[^"]*"', '')
      local class = extra and ('headline ' .. extra) or 'headline'
      return ('%s%s class="%s">%s</h%s>'):format(open, attrs, class, restructure(inner), level)
    end)
  end
  -- the contents entries, whose number is plain text of its own
  return (
    html:gsub('(<li><a href="#%w+")>(.-)</a>', function(open, inner)
      inner = inner:gsub('^(%d[%d%.]*)%s+', '<span class="section-number">%1</span> ')
      return ('%s class="headline">%s</a>'):format(open, restructure(inner))
    end)
  )
end

return M
