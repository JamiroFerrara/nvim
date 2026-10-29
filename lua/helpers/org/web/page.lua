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
    ['editor.css'] = 'text/css; charset=utf-8',
    ['editor.js'] = 'text/javascript; charset=utf-8',
    ['jarvis.css'] = 'text/css; charset=utf-8',
    ['jarvis.js'] = 'text/javascript; charset=utf-8',
    ['org.css'] = 'text/css; charset=utf-8',
    ['org-actions.js'] = 'text/javascript; charset=utf-8',
    ['roam.html'] = 'text/html; charset=utf-8',
    ['roam.css'] = 'text/css; charset=utf-8',
    ['roam.js'] = 'text/javascript; charset=utf-8',
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

--- The roam mode: notes and the link graph, also a shell the client fills.
---@return string
function M.roam()
  return M.asset 'roam.html' or '<!doctype html><p>roam assets are missing</p>'
end

local function escape(text)
  return (tostring(text or ''):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;'))
end

--- The node's own heading: keyword, priority, title, cookie, tags -- the same
--- parts, in the same classes, as a headline of the exported body
--- (helpers/org/web/headings.lua), so the page's title and the headings under
--- it are drawn by one set of rules.
---@param entry table|nil
---@return string
function M.node_title(entry)
  if not entry then
    return ''
  end
  local parts = {}
  if entry.todo then
    parts[#parts + 1] = ('<button type="button" class="state %s %s" data-entry="1" data-state="%s" title="change the state of this entry">%s</button>'):format(
      entry.done and 'done' or 'todo',
      escape(entry.todo),
      escape(entry.todo),
      escape(entry.todo)
    )
  end
  if entry.priority then
    parts[#parts + 1] = '<span class="priority">[#' .. escape(entry.priority) .. ']</span>'
  end
  parts[#parts + 1] = '<span class="title">' .. escape(entry.title) .. '</span>'
  if entry.cookie then
    parts[#parts + 1] = '<span class="cookie">' .. escape(entry.cookie) .. '</span>'
  end
  if entry.tags and #entry.tags > 0 then
    local tags = {}
    for _, tag in ipairs(entry.tags) do
      tags[#tags + 1] = '<span>' .. escape(tag) .. '</span>'
    end
    parts[#parts + 1] = '<span class="tag">' .. table.concat(tags) .. '</span>'
  end
  return '<h1 class="node-title headline">' .. table.concat(parts) .. '</h1>'
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
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#11111b">
<title>%s</title>
<link rel="stylesheet" href="/assets/org.css">
<link rel="stylesheet" href="/assets/editor.css">
<style>
  html { background: #11111b; -webkit-text-size-adjust: 100%%; text-size-adjust: 100%%; }
  body { margin: 0; }
  .wrap { max-width: 940px; margin: 0 auto; padding: 34px 30px 140px; }
  /* the page's header is the node itself: its title on the left, and the
     technical bit under it -- where the entry lives and the keys -- also
     left, so nothing in the header is pushed to a margin */
  .bar {
    display: flex; flex-direction: column; align-items: flex-start; gap: 8px;
    border-bottom: 1px solid #313244; padding-bottom: 10px; margin-bottom: 26px;
  }
  .bar .sub {
    display: flex; align-items: baseline; gap: 14px; max-width: 100%%;
    font-family: 'JetBrains Mono', ui-monospace, monospace; font-size: 11px;
    color: #6c7086;
  }
  .bar .dot { color: #45475a; transition: color 0.3s; }
  .bar .dot.on { color: #a6e3a1; }
  .bar .file { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .bar .keys { color: #45475a; }
  .empty { color: #6c7086; font-style: italic; }
  .node-title { font-family: var(--prose); font-size: 1.55em; line-height: 1.3; font-weight: 650; margin: 0; padding: 0; border: 0; }
  /* the parts of the title flow after it instead of stretching to the margins:
     the cookie and the tags belong to the title, not to the page's edges */
  .bar .node-title .title { flex: 0 1 auto; }
  .bar .node-title .tag { margin-left: 0; }
  /* a phone: the margins were drawn for a wide page and the keys are not
     there to press, so the node takes the width it has */
  @media (max-width: 720px) {
    .wrap { padding: 20px 14px calc(80px + env(safe-area-inset-bottom)); }
    .bar { margin-bottom: 20px; }
    .bar .sub { gap: 10px; font-size: 10px; }
    .bar .keys { display: none; }
    .node-title { font-size: 1.3em; }
    .org { font-size: 16px; }
  }
</style>
</head>
<body>
<div class="wrap">
  <header class="bar">
    %s
    <div class="sub"><span class="file">%s</span><span class="keys">i edit</span><span class="dot" id="live">● live</span></div>
  </header>
  <div class="org" id="content">%s</div>
</div>
<script src="/assets/org-actions.js"></script>
<script src="/assets/editor.js"></script>
<script>
  const query = %s;
  const file = %s;
  const content = document.getElementById('content');
  const live = document.getElementById('live');
  const es = new EventSource('/events');
  let timer;

  // the state badge and the checkboxes of the rendered node write the file
  // through nvim (helpers/org/web/clicks)
  const params = new URLSearchParams(query);
  const entry = { file: file, line: params.get('line'), id: params.get('id') || undefined };
  OrgActions.bind(document, entry);

  // `✕` on a headline deleted it: the node itself is gone, so the page goes
  // back to the board; a headline inside it only needs the document drawn
  // again
  document.addEventListener('org:reload', (ev) => {
    if (ev.detail && ev.detail.entry) location.assign('/');
    else refresh();
  });

  // `i` edits the node in place: the editor holds the node's own lines and
  // writes them back through nvim, which saves the file like any view
  // action. Everything else on the page stays read-only.
  document.addEventListener('keydown', (ev) => {
    if (ev.key !== 'i' || ev.metaKey || ev.ctrlKey || ev.altKey) return;
    if (ev.target.closest('textarea, input, .editor')) return;
    ev.preventDefault();
    OrgEditor.open({
      file: file,
      line: params.get('line'),
      id: params.get('id') || undefined,
      where: document.querySelector('.bar .file').textContent,
      onSaved: () => refresh(),
      onMissing: (msg) => console.warn(msg),
    });
  });

  // A snippet's copy button takes the code it sits over -- what the page
  // shows, colours dropped -- and says so for a moment.
  document.addEventListener('click', async (ev) => {
    const button = ev.target.closest('.snippet-copy');
    if (!button) return;
    const code = button.closest('.snippet')?.querySelector('pre code');
    if (!code) return;
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = 'copied';
    } catch (e) {
      button.textContent = 'no clipboard';
    }
    setTimeout(() => { button.textContent = 'copy'; }, 1600);
  });

  async function refresh() {
    try {
      const res = await fetch('/api/entry?' + query);
      const json = await res.json();
      if (json.html) content.innerHTML = json.html;
      // the heading carries the cookie, which a ticked box or a changed
      // keyword moves
      const title = document.querySelector('.node-title');
      if (json.title && title) title.outerHTML = json.title;
      // a redrawn document has no buttons of its own: they are drawn here
      OrgActions.bind(document, entry);
    } catch (e) {}
  }

  es.addEventListener('open', () => live.classList.add('on'));
  es.addEventListener('error', () => live.classList.remove('on'));
  es.addEventListener('change', (ev) => {
    let data = {};
    try { data = JSON.parse(ev.data || '{}'); } catch (e) {}
    if (data.file && data.file !== file) return;
    clearTimeout(timer);
    timer = setTimeout(refresh, 120);
  });
</script>
</body>
</html>]]):format(escape(where), M.node_title(opts.entry), escape(where), content, vim.json.encode(query), vim.json.encode(opts.file))
end

-- The viewer's metrics: the page scrolls the code to the line the link named
-- by multiplying it by the row height, so the height is a number here and
-- not something the browser is left to work out (a wrapped line would move
-- every line under it).
local ROW = 20
local TOP = 14

--- The file viewer: one file of the tree, coloured the way the editor
--- colours it, opened at the line a link named.
---@param opts { path: string, line: integer|nil, lang: string|nil, inner: string|nil, text: string|nil, error: string|nil }
---@return string
function M.file(opts)
  local where = opts.path:gsub('^' .. vim.pesc(vim.fn.expand '~'), '~')
  local title = where
  if opts.line then
    title = title .. ':' .. opts.line
  end
  local line = tonumber(opts.line) or 0
  local body
  if opts.error or not opts.text then
    body = '<p class="empty">' .. escape(opts.error or 'Nothing to show.') .. '</p>'
  else
    -- the code comes coloured from the exporter's highlighter
    -- (helpers/org/web/highlight); a language with no parser keeps plain
    -- escaped text, and the gutter is counted off the source, so both look
    -- the same
    local inner = opts.inner or escape(opts.text)
    local count = 1
    for _ in opts.text:gmatch '\n' do
      count = count + 1
    end
    local numbers = {}
    for i = 1, count do
      numbers[i] = tostring(i)
    end
    body = ('<div class="file-body" id="scroller">%s<div class="gutter">%s</div>' .. '<pre class="file-code"><code>%s</code></pre></div>'):format(
      line > 0 and '<div class="line-mark" id="mark" hidden></div>' or '',
      table.concat(numbers, '\n'),
      inner
    )
  end
  local lang = opts.lang and opts.lang ~= '' and ('<span class="lang">' .. escape(opts.lang) .. '</span>') or ''
  return ([[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#11111b">
<title>%s</title>
<link rel="stylesheet" href="/assets/org.css">
<style>
  html { background: var(--crust); -webkit-text-size-adjust: 100%%; text-size-adjust: 100%%; }
  body { margin: 0; }
  .bar {
    display: flex; align-items: center; justify-content: space-between; gap: 16px;
    height: 38px; padding: 0 18px; box-sizing: border-box;
    font-family: var(--font); font-size: 11px; color: var(--overlay);
    border-bottom: 1px solid var(--surface);
  }
  .bar .file { color: var(--subtext); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .bar .lang { color: var(--overlay); }
  .empty { font-family: var(--font); color: var(--overlay); font-style: italic; padding: 24px 18px; }
  .file-body {
    position: relative; display: flex; align-items: flex-start;
    overflow: auto; height: calc(100vh - 38px);
    font-family: var(--font); font-size: 12.5px; line-height: %dpx;
  }
  .gutter {
    position: sticky; left: 0; z-index: 1; flex: 0 0 auto;
    padding: %dpx 12px 60px 16px; text-align: right; white-space: pre;
    color: #45475a; background: var(--crust); user-select: none;
  }
  .file-code {
    margin: 0; padding: %dpx 22px 60px 2px; flex: 0 0 auto;
    white-space: pre; color: var(--text);
  }
  .file-code code { font: inherit; color: inherit; background: none; border: 0; padding: 0; }
  .line-mark {
    position: absolute; left: 0; right: 0; z-index: 0; pointer-events: none;
    background: rgba(137, 220, 235, 0.09);
    border-top: 1px solid rgba(137, 220, 235, 0.28);
    border-bottom: 1px solid rgba(137, 220, 235, 0.28);
  }
  /* a phone: the bar is a tap-height row, and the code takes the height the
     screen has left instead of the height a desktop window would */
  @media (max-width: 720px) {
    .bar { height: 52px; padding: 0 12px; font-size: 12px; }
    .file-body { height: calc(100vh - 52px); height: calc(100dvh - 52px); font-size: 13px; }
  }
</style>
</head>
<body>
<div class="bar"><span class="file">%s</span>%s</div>
%s
<script>
  // The link said which line it pointed at, so the page opens there: the
  // row height is the one the stylesheet set, and the mark sits over the
  // line, inside the scrolling body.
  (function() {
    const line = %d;
    if (!line) return;
    const scroller = document.getElementById('scroller');
    const mark = document.getElementById('mark');
    if (!scroller || !mark) return;
    const row = %d;
    const top = %d;
    mark.hidden = false;
    mark.style.top = (top + (line - 1) * row) + 'px';
    mark.style.height = row + 'px';
    scroller.scrollTop = Math.max(0, (line - 3) * row);
  })();
</script>
</body>
</html>]]):format(escape(title), ROW, TOP, TOP, escape(title), lang, body, line, ROW, TOP)
end

return M
