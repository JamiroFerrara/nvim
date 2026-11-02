-- The browser's roam mode: the org-roam index of ~/org/roam as a list of
-- notes and a graph of the links between them, and one note's body with its
-- `id:` links pointed back at this server (helpers/org/web).
--
-- The nodes and links are the plugin's own (org.extensions.roam.db), walked by
-- helpers/org/roam.lua and read from its cache here, so the page and the
-- editor's roam view (the same module) see one index: a note here is a note
-- there. The body is the HTML export the preview uses, with the anchors
-- rewritten so a click stays in the browser instead of asking it for a file it
-- cannot open.

local M = {}

local escape = (function()
  ---@param text string|nil
  ---@return string
  return function(text)
    return (tostring(text or ''):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
  end
end)()

--- The walked index (helpers.org.roam), or nil with no roam extension.
---@return table|nil
local function cached()
  return require('helpers.org.roam').index()
end

--- The file a project's knowledge base lives in.
---@param file string|nil
---@return string|nil
local function scope_file(file)
  return require('helpers.org.roam').scope_file(file)
end

--- Path of `path` from the home directory, the way the views name files.
---@param path string
---@return string
local function relative(path)
  return require('helpers.org.roam').relative(path)
end

--- Forget the walked index: the next read walks the vault again.
function M.invalidate()
  require('helpers.org.roam').invalidate()
end

--- A note's summary, the shape the rail and the graph read.
---@param node table
---@param idx table
---@return table
local function summary(node, idx)
  return {
    id = node.id,
    title = node.title,
    file = node.file,
    rel = relative(node.file),
    level = node.level,
    lnum = node.lnum,
    tags = node.tags or {},
    aliases = node.aliases or {},
    todo = node.todo,
    links = idx.outbound[node.id] or 0,
    backlinks = idx.inbound[node.id] or 0,
  }
end

--- Every note and every link between them: the roam page's whole shape.
---
--- `file` narrows the page to one project: the notes of its documentation
--- mirror (`scope_file`), plus the notes those point at -- the topics a
--- project's knowledge rests on -- with the links among the survivors. The
--- file node of a project that has no mirror yet is no node either, so the
--- scope comes out empty rather than the whole vault: a page opened on one
--- project never lists another's notes. `scope` says which project it is,
--- so the page can say so too.
---@param file string|nil a project file, or a path under the roam directory
---@return table
function M.payload(file)
  local idx = cached()
  if not idx then
    return { available = false, notes = {}, links = {}, stats = { nodes = 0, links = 0, files = 0 } }
  end
  local scope
  local keep
  if file and file ~= '' then
    scope = scope_file(file)
    if scope then
      local own = {}
      for _, node in ipairs(idx.nodes) do
        if node.file == scope then
          own[node.id] = true
        end
      end
      -- the project's own notes, then one hop out: the topics they name.
      -- `own` stays read-only, so a topic's own links do not pull the whole
      -- graph back in
      keep = {}
      for id in pairs(own) do
        keep[id] = true
      end
      for _, edge in ipairs(idx.edges) do
        if own[edge.source] then
          keep[edge.target] = true
        end
      end
    end
  end
  local links = {}
  for _, edge in ipairs(idx.edges) do
    if not keep or (keep[edge.source] and keep[edge.target]) then
      links[#links + 1] = edge
    end
  end
  local notes, files = {}, {}
  for _, node in ipairs(idx.nodes) do
    if not keep or keep[node.id] then
      notes[#notes + 1] = summary(node, idx)
      files[node.file] = true
    end
  end
  table.sort(notes, function(a, b)
    return a.title:lower() < b.title:lower()
  end)
  local nfiles = 0
  for _ in pairs(files) do
    nfiles = nfiles + 1
  end
  local out = {
    available = true,
    notes = notes,
    links = links,
    stats = { nodes = #notes, links = #links, files = nfiles },
  }
  if scope then
    out.scope = { file = scope, name = (vim.fs.basename(scope):gsub('%.org$', '')) }
  end
  return out
end

--- Point the anchors of an exported body at this server.
---
--- A link to a node in another file comes out of the export as the text
--- `[BROKEN LINK: <uuid>]`: the exporter asks org.id for the file and reads
--- a field name the lookup does not use, so it never finds one (the ids
--- themselves are there, and the roam index knows every one of them). The
--- marker is replaced here by the link the reader meant, labelled with the
--- node's own title. An `id:` link the export *did* resolve (`path#ID-...`)
--- takes the same route, and its text becomes the title too when the link
--- carried no description. Anything else is left as it came.
---@param html string
---@param idx table
---@return string
local function rewrite(html, idx)
  html = html:gsub('%[BROKEN LINK: ([%w%-]+)%]', function(target)
    local node = idx.by_id[target]
    if not node then
      return nil
    end
    return ('<a class="roam-link" href="#n=%s">%s</a>'):format(node.id, escape(node.title))
  end)
  html = html:gsub('<a href="([^"]-)#ID%-([%w%-]+)"([^>]*)>(.-)</a>', function(_, target, attrs, desc)
    local node = idx.by_id[target]
    if not node then
      return '<span class="broken-link">' .. desc .. '</span>'
    end
    local text = desc
    if text == '' or text:match '%.org$' or text == target then
      text = escape(node.title)
    end
    return ('<a class="roam-link" href="#n=%s"%s>%s</a>'):format(target, attrs, text)
  end)
  -- a `[[file:note.org]]` link to another note: the exporter writes the
  -- target as the `.html` it would publish, which no browser can open; the
  -- note is here, so the link goes to it
  html = html:gsub('<a href="file://([^"#]+)%.html"([^>]*)>(.-)</a>', function(path, attrs, desc)
    local node = idx.by_file[vim.uri_decode(path) .. '.org']
    if not node then
      return nil
    end
    return ('<a class="roam-link" href="#n=%s">%s</a>'):format(node.id, desc)
  end)
  return html
end

--- One note: its summary, its rendered body and the notes on both sides of
--- it.
---@param id string
---@return table|nil note, string|nil error
function M.note(id)
  local idx = cached()
  if not idx then
    return nil, 'org-roam is not configured'
  end
  local node = idx.by_id[id]
  if not node then
    return nil, 'no such node'
  end
  local ok, html, err = pcall(function()
    return require('helpers.org.web.actions').entry_html({
      file = node.file,
      -- a file node is the whole file, a headline node its subtree
      line = node.level > 0 and node.lnum or nil,
    }, { with_toc = false })
  end)
  if not ok then
    return nil, tostring(html)
  end
  if not html then
    return nil, err or 'could not render this note'
  end
  local function related(pairs)
    local out = {}
    for _, pair in ipairs(pairs) do
      out[#out + 1] = {
        id = pair.source.id,
        title = pair.source.title,
        rel = relative(pair.source.file),
        lnum = pair.source.lnum,
      }
    end
    table.sort(out, function(a, b)
      return a.title:lower() < b.title:lower()
    end)
    return out
  end
  local backlinks, outgoing = {}, {}
  for _, edge in ipairs(idx.edges) do
    if edge.source == id and idx.by_id[edge.target] then
      outgoing[#outgoing + 1] = { source = idx.by_id[edge.target] }
    elseif edge.target == id and idx.by_id[edge.source] then
      backlinks[#backlinks + 1] = { source = idx.by_id[edge.source] }
    end
  end
  local note = summary(node, idx)
  note.html = rewrite(html, idx)
  note.olp = node.olp or {}
  note.backlinks = related(backlinks)
  note.outbound = related(outgoing)
  return note, nil
end

return M
