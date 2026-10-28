-- What a rendered document can be asked to do (helpers/org/web): the state
-- of a headline and the checkbox of a list item.
--
-- org.nvim's HTML export writes a headline's keyword as a badge to read --
-- `<span class="todo NEXT">NEXT</span>`, laid out as one part of the row by
-- helpers/org/web/headings -- and a checkbox as an `<input>` only the page
-- can tick. Both are given here the place they stand for: the nth checkbox
-- item of the entry's subtree, the nth headline under it, so a click can
-- name its own line on the other side (helpers/org/web/actions) instead of
-- the page guessing at file positions.
--
-- The document is walked in its own order, and the exporter writes a list
-- item and a headline as it meets them in the buffer: the nth of each in the
-- page is the nth of each in the file. A headline is still matched by its
-- title, so one the exporter dropped (a COMMENT tree, a folded subtree) does
-- not shift the ones after it -- that one stays a badge to read.
local M = {}

--- The letters and digits of a piece of text, lowercased: what two spellings
--- of one title have in common once the markup around them is gone.
---@param text string|nil
---@return string
local function alnum(text)
  return (tostring(text or ''):lower():gsub('[^%w]', ''))
end

local ENTITIES = {
  ['&nbsp;'] = ' ',
  ['&amp;'] = '&',
  ['&lt;'] = '<',
  ['&gt;'] = '>',
  ['&quot;'] = '"',
}

--- The text a run of inline HTML shows, with its tags and entities gone.
---@param html string
---@return string
local function plain(html)
  local text = html:gsub('<[^>]*>', '')
  text = text:gsub('&#?%w+;', ENTITIES)
  return (text:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function escape(text)
  return (tostring(text):gsub('&', '&amp;'):gsub('"', '&quot;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

--- A checkbox the page may tick, numbered in document order and carrying the
--- item's own text, so a list that moved under the render can still be
--- answered by what it says. The exporter writes the box as `<code>[X]</code>`
--- text (`html_checkbox_type` is a config word, and one page is no reason to
--- change it for every export); it becomes a real `input` here. Without an
--- entry to write to it stays an inert control, not a button that answers
--- nothing.
---@param html string
---@param writable boolean
---@return string
local function boxes(html, writable)
  local n = 0
  return (
    html:gsub('<li class="([%a]+)"><code>%[[^%]]*%]</code>%s*([^<]*)', function(class, text)
      if not (class == 'on' or class == 'off' or class == 'trans') then
        return nil
      end
      n = n + 1
      if not writable then
        return ('<li class="%s"><input type="checkbox" disabled>%s'):format(class, text)
      end
      local checked = class == 'on' and ' checked' or ''
      return ('<li class="%s"><input type="checkbox" data-box="%d" data-text="%s"%s>%s'):format(class, n, escape(plain(text)), checked, text)
    end)
  )
end

--- The title a heading is drawn with: its own span, its cookie aside.
---@param inner string the heading's inner HTML
---@return string html
local function title_of(inner)
  local rest = inner:gsub('<span class="cookie">.-</span>', '')
  return rest:match '<span class="title">(.-)</span>' or ''
end

--- The place `text` names among `headlines`, from `at` on: the title itself,
--- else the one headline containing it, when only one does.
---@param headlines table[] { title: string } in file order
---@param at integer 1-based place to start from
---@param text string what the page drew
---@return integer|nil
local function place(headlines, at, text)
  local want = alnum(text)
  if want == '' then
    return nil
  end
  for i = at, #headlines do
    if alnum(headlines[i].title) == want then
      return i
    end
  end
  local found
  for i = at, #headlines do
    local have = alnum(headlines[i].title)
    if #have >= 3 and (want:find(have, 1, true) or have:find(want, 1, true)) then
      if found then
        return nil
      end
      found = i
    end
  end
  return found
end

--- One heading, its keyword a button when the page can write it.
---@param open string the `<hN …` opening tag and its `>`
---@param inner string
---@param index integer|nil the place of the headline it names
---@param text string
---@param writable boolean
---@return string
local function heading(open, inner, index, text, writable)
  local classes, label = inner:match '<span class="([td][^"]*)">([^<]*)</span>'
  if writable and index and label then
    local button = ('<button type="button" class="state %s" data-heading="%d" data-text="%s" title="change the state of this headline">%s</button>'):format(
      classes,
      index,
      escape(text),
      label
    )
    inner = inner:gsub('<span class="[td][^"]*">[^<]*</span>', button, 1)
    open = open:gsub('>$', (' data-heading="%d">'):format(index))
  end
  return open .. inner
end

--- Give every heading its place, and its keyword a button; number every
--- checkbox. `headlines` are the entry's own under-headlines in file order,
--- and the entry must be known for either to be writable.
---@param html string|nil
---@param opts { headlines?: table[], writable?: boolean }
---@return string|nil
function M.html(html, opts)
  if type(html) ~= 'string' or html == '' then
    return html
  end
  opts = opts or {}
  local headlines = opts.headlines or {}
  local writable = opts.writable == true
  local out, at, cursor = {}, 1, 1
  while true do
    local start, stop, level = html:find('<h(%d)[^>]-class="headline"', at)
    if not start then
      break
    end
    local open_end = html:find('>', stop, true)
    local close = open_end and html:find('</h' .. level .. '>', open_end, true)
    if not close then
      break
    end
    local text = plain(title_of(html:sub(open_end + 1, close - 1)))
    local index = place(headlines, cursor, text)
    if index then
      cursor = index + 1
    end
    out[#out + 1] = html:sub(at, start - 1)
    out[#out + 1] = heading(html:sub(start, open_end), html:sub(open_end + 1, close - 1), index, text, writable)
    at = close
  end
  out[#out + 1] = html:sub(at)
  return boxes(table.concat(out), writable)
end

return M
