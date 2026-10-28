-- The browser's roam mode: the org-roam index of ~/org/roam as a list of
-- notes and a graph of the links between them, and one note's body with its
-- `id:` links pointed back at this server (helpers/org/web).
--
-- The nodes and links are the plugin's own (org.extensions.roam.db), so a
-- note here is a note in the editor: every file and every headline carrying
-- an `:ID:` is a node, and a link is the `id:` link the roam capture wrote.
-- The body is the HTML export the preview uses, with the anchors rewritten
-- so a click stays in the browser instead of asking it for a file it cannot
-- open.

local M = {}

local escape = (function()
  ---@param text string|nil
  ---@return string
  return function(text)
    return (tostring(text or ''):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
  end
end)()

--- The roam extension's index, when the extension is configured.
---@return table|nil
local function index_db()
  local ok, ext = pcall(require, 'org.extensions')
  if not ok or not ext.opts 'roam' then
    return nil
  end
  local ok_db, db = pcall(require, 'org.extensions.roam.db')
  if not ok_db then
    return nil
  end
  return db
end

--- Path of `path` from the home directory, the way the views name files.
---@param path string
---@return string
local function relative(path)
  local home = vim.fs.normalize(vim.fn.expand '~')
  if vim.startswith(path, home .. '/') then
    return path:sub(#home + 2)
  end
  return path
end

local cache = { at = 0, value = nil }

function M.invalidate()
  cache.value = nil
end

--- The index walked once: nodes by id, the file-level node of every file, the
--- node ids an `id:` link can reach, and the edges between notes.
---@return table|nil
local function walk()
  local db = index_db()
  if not db then
    return nil
  end
  if not pcall(db.sync) then
    return nil
  end
  local nodes = db.nodes() or {}
  local by_id, by_file = {}, {}
  local files = {}
  for _, node in ipairs(nodes) do
    by_id[node.id] = node
    if node.level == 0 then
      by_file[node.file] = node
    end
    files[node.file] = true
  end
  -- one edge per pair: the graph is about notes, not about how many times
  -- one note says the other's name
  local edges, seen = {}, {}
  local outbound, inbound = {}, {}
  for _, link in ipairs(db.links() or {}) do
    local target = link.type == 'id' and by_id[link.path] or nil
    if target and link.source and by_id[link.source] and target.id ~= link.source then
      local key = link.source .. '\0' .. target.id
      if not seen[key] then
        seen[key] = true
        edges[#edges + 1] = { source = link.source, target = target.id }
        outbound[link.source] = (outbound[link.source] or 0) + 1
        inbound[target.id] = (inbound[target.id] or 0) + 1
      end
    end
  end
  local nfiles = 0
  for _ in pairs(files) do
    nfiles = nfiles + 1
  end
  return {
    nodes = nodes,
    by_id = by_id,
    by_file = by_file,
    edges = edges,
    outbound = outbound,
    inbound = inbound,
    stats = { nodes = #nodes, links = #edges, files = nfiles },
  }
end

--- The walked index, cached for a moment so the page and a note's body do
--- not sync the directory twice in one load.
---@return table|nil
local function cached()
  local now = (vim.uv or vim.loop).hrtime() / 1e6
  if cache.value and now - cache.at < 1500 then
    return cache.value
  end
  local value = walk()
  if value then
    cache.value, cache.at = value, now
  end
  return value
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
---@return table
function M.payload()
  local idx = cached()
  if not idx then
    return { available = false, notes = {}, links = {}, stats = { nodes = 0, links = 0, files = 0 } }
  end
  local notes = {}
  for _, node in ipairs(idx.nodes) do
    notes[#notes + 1] = summary(node, idx)
  end
  table.sort(notes, function(a, b)
    return a.title:lower() < b.title:lower()
  end)
  return { available = true, notes = notes, links = idx.edges, stats = idx.stats }
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
