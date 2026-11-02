-- The `#+begin_src markdown` blocks of the browser views (helpers/org/web).
-- An agent's hand-back is one: prose with **bold** labels, `code` spans,
-- bullets, and a fenced hunk under each change. org.nvim's export writes the
-- block as a single <pre>, so the page showed the markdown source instead of
-- the piece it describes -- the hunk in the same monospace run as the
-- sentence above it, its fences and backticks still in the text.
--
-- This renders the subset those blocks actually use -- paragraphs, headings,
-- bullets and numbered lists, fenced code, tables and quotes -- with the
-- inline markup resolved, and hands every fenced block and every link back
-- to the shared pieces: a fence becomes the same titled snippet a source
-- block of its own becomes (highlight.snippet), so a hunk reads as code and
-- not as text.
local M = {}

local function escape(text)
  return (text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
end

local function highlight()
  return require 'helpers.org.web.highlight'
end

--- A link in the vault or on the web. A `file:` target has no page to open
--- in the browser, so it keeps its label as a code span and carries the path
--- in its title; an http one is a real link.
---@param target string
---@param label string already-escaped inline HTML
---@return string
local function link(target, label)
  if target:match '^https?://' or target:match '^mailto:' then
    return ('<a href="%s" target="_blank" rel="noreferrer">%s</a>'):format(escape(target), label)
  end
  return ('<code class="file-ref" title="%s">%s</code>'):format(escape(target), label)
end

--- One line of markdown as inline HTML: code spans, links, bold, italic. The
--- pieces that must not be touched again (a code span's backticks would be
--- read as emphasis) are stashed and put back at the end.
---@param text string
---@return string
local function inline(text)
  local stash = {}
  local function keep(html)
    stash[#stash + 1] = html
    return '\1' .. #stash .. '\1'
  end

  text = text:gsub('(`+)(.-)%1', function(_, code)
    return keep('<code>' .. escape(code) .. '</code>')
  end)
  text = text:gsub('%[%[([^%]]+)%]%[([^%]]*)%]%]', function(target, label)
    return keep(link(target, escape(label ~= '' and label or target)))
  end)
  text = text:gsub('%[%[([^%]]+)%]%]', function(target)
    return keep(link(target, escape(target)))
  end)
  text = text:gsub('%[([^%]]+)%]%(([^%s%)]+)%)', function(label, url)
    return keep(link(url, escape(label)))
  end)

  text = escape(text)
  -- bold italic first: a run of three would otherwise be read as bold with a
  -- stray star on each side
  text = text:gsub('%*%*%*(%S.-)%*%*%*', '<strong><em>%1</em></strong>')
  text = text:gsub('%*%*(%S.-)%*%*', '<strong>%1</strong>')
  text = text:gsub('__(%S.-)__', '<strong>%1</strong>')
  -- a star or an underscore opens emphasis only before a non-space, so the
  -- arithmetic in `2 * 3 * 4` and a lone star stay as they are written; an
  -- underscore inside a word is part of the word (snake_case), so it needs a
  -- non-word character before it
  text = text:gsub('%*(%S.-)%*', '<em>%1</em>')
  text = text:gsub('([^%w])_(%S.-)_', '%1<em>%2</em>')
  text = text:gsub('^_(%S.-)_', '<em>%1</em>')

  return (text:gsub('%\1(%d+)%\1', function(index)
    return stash[tonumber(index)]
  end))
end

--- A fenced block as a snippet: the title bar names the language and, when
--- the hunk names one, the file it came from; the body is coloured the way
--- the editor colours it.
---@param lang string
---@param code string
---@param ref? { label: string, href: string, title: string }
---@return string
local function fence(lang, code, ref)
  local hl = highlight()
  return hl.snippet(lang, hl.code(code, lang) or escape(code), ref)
end

--- The `→ [[file:path::62][label]]` line a hunk is followed by, as the
--- snippet bar's file. The line number rides as the anchor the browser's link
--- rewrite reads (helpers/org/web/links), so the name opens the file at the
--- hunk; a target with no line number is linked as it stands. The rest of the
--- line comes back too: the link shares it with the sentence it belongs to.
---@param line string
---@return { label: string, href: string, title: string }|nil ref, string|nil rest
local function file_ref(line)
  local target, label, rest = line:match '^%s*→%s*%[%[file:(.-)%]%[([^%]]*)%]%](.*)$'
  if not target then
    return nil
  end
  local path, number = target:match '^(.-)::#omp%-l(%d+)$'
  if not path then
    path, number = target:match '^(.-)::(%d+)$'
  end
  local href = path or target
  if href:sub(1, 2) == '~/' then
    href = vim.fn.expand '~' .. href:sub(2)
  end
  local ref = {
    label = label ~= '' and label or target,
    href = 'file:' .. href .. (path and ('#omp-l' .. number) or ''),
    title = 'file:' .. target,
  }
  return ref, rest
end

local function fence_open(line)
  local marks, info = line:match '^%s*([`~]+)%s*(.-)%s*$'
  if not marks or #marks < 3 then
    return nil
  end
  return marks, (info:match '^([%w%+%#%._%-]*)') or ''
end

local function bullet(line)
  local indent, text = line:match '^(%s*)[-*+]%s+(.*)$'
  if indent then
    return indent, false, text
  end
  indent, text = line:match '^(%s*)%d+[.)]%s+(.*)$'
  if indent then
    return indent, true, text
  end
  return nil
end

local is_sep = function(line)
  return line:match '^%s*|?[%-:|+]+$' ~= nil and line:match '%-' ~= nil
end

local function cells(line)
  local row = {}
  for cell in (line:gsub('^%s*|', ''):gsub('|%s*$', '') .. '|'):gmatch '(.-)|' do
    row[#row + 1] = cell:match '^%s*(.-)%s*$'
  end
  return row
end

--- The list a run of items draws: a node per item, its own items nested under
--- it, each level rendered as the list its marker asked for.
---@param items { indent: integer, ordered: boolean, html: string }[]
---@return string
local function render_list(items)
  local base = math.huge
  for _, item in ipairs(items) do
    base = math.min(base, item.indent)
  end

  local root = { children = {} }
  local stack = { { level = -1, node = root } }
  for _, item in ipairs(items) do
    local level = math.floor((item.indent - base) / 2)
    while #stack > 1 and stack[#stack].level >= level do
      table.remove(stack)
    end
    local node = { html = item.html, ordered = item.ordered, children = {} }
    local parent = stack[#stack].node
    parent.children[#parent.children + 1] = node
    stack[#stack + 1] = { level = level, node = node }
  end

  local function emit(node)
    local tag = node.children[1] and node.children[1].ordered and 'ol' or 'ul'
    local out = { '<' .. tag .. '>' }
    for _, child in ipairs(node.children) do
      out[#out + 1] = '<li>' .. child.html
      if #child.children > 0 then
        out[#out + 1] = emit(child)
      end
      out[#out + 1] = '</li>'
    end
    out[#out + 1] = '</' .. tag .. '>'
    return table.concat(out)
  end

  return emit(root)
end

--- Render markdown source as HTML. Markdown this does not know -- a stray
--- construct, a line of plain text -- becomes a paragraph of its own text, so
--- nothing is dropped.
---@param code string
---@return string
function M.render(code)
  local lines = {}
  for line in (code .. '\n'):gmatch '(.-)\n' do
    lines[#lines + 1] = line
  end
  if lines[#lines] == '' then
    lines[#lines] = nil
  end

  local out = {}
  local i, n = 1, #lines
  while i <= n do
    local line = lines[i]
    if line:match '^%s*$' then
      i = i + 1
    else
      local marks, lang = fence_open(line)
      local indent, ordered, text = bullet(line)
      local level, header = line:match '^%s*(#+)%s+(.*)$'
      local quote = line:match '^%s*>%s?(.*)$'

      if marks then
        local char = marks:sub(1, 1)
        local body = {}
        i = i + 1
        while i <= n and not lines[i]:match('^%s*' .. (char == '`' and '`' or '~') .. '+%s*$') do
          body[#body + 1] = lines[i]
          i = i + 1
        end
        i = i + 1 -- the closing fence
        -- a hunk names its file on the line under it, the way a hand-back
        -- writes it: that name goes into the snippet's bar instead of
        -- repeating under the code, and what the line says after the link
        -- stays the paragraph it started
        local ref
        local j = i
        while j <= n and lines[j]:match '^%s*$' do
          j = j + 1
        end
        if j <= n then
          local rest
          ref, rest = file_ref(lines[j])
          if ref then
            rest = rest:match '^%s*(.-)%s*$'
            if rest == '' then
              i = j + 1
            else
              lines[j] = rest
              i = j
            end
          end
        end
        out[#out + 1] = fence(lang, table.concat(body, '\n'), ref)
      elseif indent then
        local items, item = {}, nil
        while i <= n do
          local ind, num, body = bullet(lines[i])
          if ind then
            item = { indent = #ind, ordered = num, parts = { body } }
            items[#items + 1] = item
            i = i + 1
          elseif lines[i]:match '^%s*$' then
            local next_line = lines[i + 1]
            local _, _, follow = next_line and bullet(next_line)
            if follow or not (next_line and next_line:match '^%s+%S') then
              break
            end
            i = i + 1
          elseif item and lines[i]:match '^%s+%S' then
            item.parts[#item.parts + 1] = (lines[i]:gsub('^%s+', ''))
            i = i + 1
          else
            break
          end
        end
        for _, it in ipairs(items) do
          it.html = inline(table.concat(it.parts, ' '))
        end
        out[#out + 1] = render_list(items)
      elseif level then
        local tag = 'h' .. math.min(#level + 1, 6)
        out[#out + 1] = ('<%s>%s</%s>'):format(tag, inline(header), tag)
        i = i + 1
      elseif quote then
        local body = {}
        while i <= n and lines[i]:match '^%s*>' do
          body[#body + 1] = (lines[i]:gsub('^%s*>%s?', ''))
          i = i + 1
        end
        out[#out + 1] = '<blockquote>' .. inline(table.concat(body, ' ')) .. '</blockquote>'
      elseif line:match '^%s*|' then
        local head = cells(line)
        local rows, align = {}, 1
        if lines[i + 1] and is_sep(lines[i + 1]) then
          align = 2
        end
        i = i + align
        while i <= n and lines[i]:match '^%s*|' and not is_sep(lines[i]) do
          rows[#rows + 1] = cells(lines[i])
          i = i + 1
        end
        local function row(cells_of, tag)
          local parts = { '<tr>' }
          for _, cell in ipairs(cells_of) do
            parts[#parts + 1] = ('<%s>%s</%s>'):format(tag, inline(cell), tag)
          end
          parts[#parts + 1] = '</tr>'
          return table.concat(parts)
        end
        local html = { '<table>' }
        if align == 2 then
          html[#html + 1] = '<thead>' .. row(head, 'th') .. '</thead>'
        end
        html[#html + 1] = '<tbody>'
        if align == 1 then
          html[#html + 1] = row(head, 'th')
        end
        for _, cells_of in ipairs(rows) do
          html[#html + 1] = row(cells_of, 'td')
        end
        html[#html + 1] = '</tbody></table>'
        out[#out + 1] = table.concat(html)
      else
        local body = {}
        while i <= n and not lines[i]:match '^%s*$' do
          local stop = fence_open(lines[i]) or bullet(lines[i]) or lines[i]:match '^%s*#' or lines[i]:match '^%s*[>|]'
          if stop then
            break
          end
          body[#body + 1] = (lines[i]:gsub('^%s+', ''))
          i = i + 1
        end
        if #body == 0 then -- a block construct the loop did not take: keep the line
          body[1] = (line:gsub('^%s+', ''))
          i = i + 1
        end
        out[#out + 1] = '<p>' .. inline(table.concat(body, ' ')) .. '</p>'
      end
    end
  end
  return table.concat(out, '\n')
end

return M
