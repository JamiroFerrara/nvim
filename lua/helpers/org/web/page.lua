-- Documents the web server hands out (helpers/org/web/init.lua): the
-- dashboard shell and the single-entry preview page, plus the assets both
-- read.
local M = {}

local assets_dir = (function()
  local source = debug.getinfo(1, 'S').source:gsub('^@', '')
  return vim.fs.dirname(source) .. '/assets'
end)()

--- Read a file from the assets directory. Only the files listed here are
--- served, so a request cannot walk out of it.
---@param name string
---@return string|nil body, string|nil mime
function M.asset(name)
  local mime = {
    ['index.html'] = 'text/html; charset=utf-8',
    ['app.css'] = 'text/css; charset=utf-8',
    ['app.js'] = 'text/javascript; charset=utf-8',
    ['org.css'] = 'text/css; charset=utf-8',
  }
  if not mime[name] then
    return nil
  end
  local fd = io.open(assets_dir .. '/' .. name, 'r')
  if not fd then
    return nil
  end
  local body = fd:read '*a'
  fd:close()
  return body, mime[name]
end

--- The dashboard: a shell; the client fetches the data itself.
---@return string
function M.dashboard()
  return M.asset 'index.html' or '<!doctype html><p>dashboard assets are missing</p>'
end

local function escape(text)
  return (tostring(text or ''):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
end

--- The node's own heading: keyword, priority, title, tags.
---@param entry table|nil
---@return string
local function node_title(entry)
  if not entry then
    return ''
  end
  local parts = {}
  if entry.todo then
    parts[#parts + 1] = ('<span class="%s %s">%s</span>'):format(entry.done and 'done' or 'todo', escape(entry.todo), escape(entry.todo))
  end
  if entry.priority then
    parts[#parts + 1] = '<span class="priority">[#' .. escape(entry.priority) .. ']</span> '
  end
  parts[#parts + 1] = escape(entry.title)
  if entry.cookie then
    parts[#parts + 1] = ' <code>' .. escape(entry.cookie) .. '</code>'
  end
  if entry.tags and #entry.tags > 0 then
    local tags = {}
    for _, tag in ipairs(entry.tags) do
      tags[#tags + 1] = '<span>' .. escape(tag) .. '</span>'
    end
    parts[#parts + 1] = '<span class="tag">' .. table.concat(tags) .. '</span>'
  end
  return '<h1 class="node-title">' .. table.concat(parts) .. '</h1>'
end

--- The preview page: one node's subtree, exported by org.nvim, reloading
--- itself as the buffer changes.
---@param opts { file: string, line: integer|nil, html: string|nil, error: string|nil, entry: table|nil }
---@return string
function M.preview(opts)
  local where = opts.file:gsub('^' .. vim.pesc(vim.fn.expand '~'), '~')
  if opts.line then
    where = where .. ':' .. opts.line
  end
  local content = opts.html
  if not content or content == '' then
    content = '<p class="empty">' .. escape(opts.error or 'This node has no body.') .. '</p>'
  end
  local query = 'file=' .. vim.uri_encode(opts.file, 'rfc3986')
  if opts.line then
    query = query .. '&line=' .. opts.line
  end
  return ([[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<link rel="stylesheet" href="/assets/org.css">
<style>
  html { background: #11111b; }
  body { margin: 0; }
  .wrap { max-width: 940px; margin: 0 auto; padding: 34px 30px 140px; }
  .bar {
    display: flex; align-items: center; justify-content: space-between; gap: 16px;
    font-family: 'JetBrains Mono', ui-monospace, monospace; font-size: 11px;
    color: #6c7086; border-bottom: 1px solid #313244; padding-bottom: 10px; margin-bottom: 26px;
  }
  .bar .dot { color: #45475a; transition: color 0.3s; }
  .bar .dot.on { color: #a6e3a1; }
  .bar .file { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .empty { color: #6c7086; font-style: italic; }
  .node-title { font-family: 'Inter', system-ui, sans-serif; font-size: 1.6em; line-height: 1.3; margin: 0 0 1.4em; color: #cdd6f4; }
</style>
</head>
<body>
<div class="wrap">
  <div class="bar"><span class="file">%s</span><span class="dot" id="live">● live</span></div>
  %s
  <div class="org" id="content">%s</div>
</div>
<script>
  const query = %s;
  const content = document.getElementById('content');
  const live = document.getElementById('live');
  const es = new EventSource('/events');
  let timer;
  es.addEventListener('open', () => live.classList.add('on'));
  es.addEventListener('error', () => live.classList.remove('on'));
  es.addEventListener('change', (ev) => {
    let data = {};
    try { data = JSON.parse(ev.data || '{}'); } catch (e) {}
    if (data.file && data.file !== %s) return;
    clearTimeout(timer);
    timer = setTimeout(async () => {
      try {
        const res = await fetch('/api/entry?' + query);
        const json = await res.json();
        if (json.html) content.innerHTML = json.html;
      } catch (e) {}
    }, 120);
  });
</script>
</body>
</html>]]):format(
    escape(where),
    escape(where),
    node_title(opts.entry),
    content,
    vim.json.encode(query),
    vim.json.encode(opts.file)
  )
end

return M
