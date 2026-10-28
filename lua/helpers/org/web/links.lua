-- File links in the browser views (helpers/org/web): a `[[file:...]]` in a
-- node's body opens the file it names instead of going nowhere.
--
-- Two things stand between the browser and that. org.nvim's HTML export writes
-- the link as `file:///abs/path`, a scheme no browser follows from a page, so
-- a click does nothing. And the export resolves a `::62` search option against
-- the target's contents and gives up on the whole document when nothing
-- matches -- while an org reader reads a bare number as a line
-- (org/links/open.lua), which is how these links are written. So the export
-- runs on a copy of the lines whose line numbers are turned into a custom-id
-- search (`::#omp-l62`, which resolves without reading anything), and the
-- hrefs it writes come back as links to the file viewer (/file).
local M = {}

local MARKER = 'omp-l'

-- a `[[file:path::62]` target: the number goes behind the marker, the rest of
-- the link (its description, its other half) is copied as written
local LINE_SEARCH = '(%[%[file:[^%]]-)::(%d+)%]'

--- The lines to export, with a `::62` search option marked as a line number.
--- Every other line comes back as it was.
---@param lines string[]
---@return string[]
function M.lines(lines)
  local out = {}
  for i, line in ipairs(lines) do
    if line:find('[[file:', 1, true) then
      out[i] = line:gsub(LINE_SEARCH, function(head, number)
        return head .. '::#' .. MARKER .. number .. ']'
      end)
    else
      out[i] = line
    end
  end
  return out
end

--- `%20` -> ` `, `%E2%82%AC` -> `€`.
---@param text string
---@return string
local function decode(text)
  return (text:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

--- The file an href names, absolute and normalised, and the line its anchor
--- marks -- or nil when the href is no file link at all (a URL, an anchor,
--- a radio target).
---@param href string
---@param base string|nil directory a relative link is taken from
---@return string|nil path, integer|nil line
local function target(href, base)
  if href == '' or href:sub(1, 1) == '#' then
    return nil
  end
  local path, anchor = href:match '^(.-)#(.*)$'
  path = path or href
  if path:match '^file:' then
    path = decode(path:sub(6))
    -- file:///home/x, and the two-slash and one-slash spellings of it
    path = path:gsub('^//+', '/')
    -- file:///C:/x is a Windows path, not a rooted one
    path = path:gsub('^(/%a:[/\\])', function(m)
      return m:sub(2)
    end)
  elseif path:match '^%a[%w+.%-]*:' then
    return nil
  else
    path = decode(path)
  end
  if path:sub(1, 1) ~= '/' and not path:match '^%a:[/\\]' then
    if not base then
      return nil
    end
    path = base .. '/' .. path
  end
  local line = anchor and anchor:match('^' .. vim.pesc(MARKER) .. '(%d+)$')
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p')), line and tonumber(line) or nil
end

--- Rewrite every file link of an exported document to a link to the file
--- viewer, keeping its description and its other attributes, and opening the
--- file in its own tab -- the dashboard a reader clicked from stays where it
--- was. A link whose file is not there is left exactly as it was written.
---@param html string|nil
---@param base string|nil directory a relative link is taken from
---@return string|nil
function M.html(html, base)
  if type(html) ~= 'string' or html == '' then
    return html
  end
  return (
    html:gsub('<a href="([^"#][^"]*)"([^>]*)>', function(href, attrs)
      local path, line = target(href, base)
      if not path or not vim.uv.fs_stat(path) then
        return nil
      end
      local query = '/file?path=' .. vim.uri_encode(path, 'rfc3986')
      if line then
        query = query .. '&amp;line=' .. line
      end
      -- a markdown link already carries its own target (helpers/org/web/markdown)
      if not attrs:match 'target=' then
        attrs = ' target="_blank" rel="noopener"' .. attrs
      end
      return '<a href="' .. query .. '"' .. attrs .. '>'
    end)
  )
end

return M
