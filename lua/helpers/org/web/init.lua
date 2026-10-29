-- The org browser views: a dashboard of every TODO in the vault, and a
-- rendered preview of the node under the cursor.
--
-- Both are served by one HTTP server that runs inside nvim, on a loopback
-- port. The dashboard is the TODO views of this config, sectioned and sorted
-- by helpers/org/web/data.lua; the preview is one subtree exported by
-- org.nvim's own HTML back end (org.export). Writes (a keyword change, "open
-- in editor") come back through /api, land in nvim, and go out through
-- org.nvim -- so the CLOSED stamp, the logging drawer and the parent cookies
-- land exactly where the editor would put them.
--
-- Pages follow the vault: an fs watcher over ~/org (helpers/org/watch.lua)
-- and TextChanged events broadcast on the event stream, and the browser
-- refetches. They follow the site too: an edit to an asset or to one of the
-- renderer modules is broadcast as `reload` (helpers/org/web/hot.lua), and the
-- open pages load themselves again without a manual refresh. The server
-- listens on the loopback address only, the way markdown-preview.nvim's does.
--
-- The phone reaches the same pages through an ngrok tunnel started beside the
-- server (helpers/org/web/share.lua): its address and the QR of it are the
-- rail's last card, and `:OrgWebShare` copies it and opens the page that
-- draws it. `g:org_web_share = false` keeps the vault off a public address.
--
-- The dashboard carries the voice card (`/api/voice`, drawn by
-- assets/jarvis.js): the click starts a conversation in helpers/org/voice.lua
-- -- record, report the level and the words so far, transcribe, then an `omp`
-- pane seeded with the words -- and the page polls the phase, the level and
-- the words it draws from the same route. A page running on a device with a
-- microphone of its own records with it and streams the sound up
-- (`/api/voice/audio`), so the phone speaks into the phone rather than into
-- the machine running nvim.
local M = {}

local actions = require 'helpers.org.web.actions'
local data = require 'helpers.org.web.data'
local hot = require 'helpers.org.web.hot'
local http = require 'helpers.org.web.http'
local page = require 'helpers.org.web.page'
local roam = require 'helpers.org.web.roam'
local share = require 'helpers.org.web.share'

local state = {
  server = nil,
  port = nil,
  timer = nil,
  hot = nil,
}

-- where these files live: the site's own assets are the directory beside them
local web_dir = vim.fs.dirname((debug.getinfo(1, 'S').source:gsub('^@', '')))

local uv = vim.uv or vim.loop

local function is_wsl()
  if vim.env.WSL_DISTRO_NAME and vim.env.WSL_DISTRO_NAME ~= '' then
    return true
  end
  local release = uv.os_uname().release or ''
  return release:lower():find('microsoft', 1, true) ~= nil
end

local function json(res, value, status)
  res.send(status or 200, 'application/json; charset=utf-8', vim.json.encode(value))
end

---@param req table
---@return table
local function payload_of(req)
  local ok, decoded = pcall(vim.json.decode, req.body or '')
  return ok and type(decoded) == 'table' and decoded or {}
end

local function encode(text)
  return vim.uri_encode(text or '', 'rfc3986')
end

local function keyword_lists()
  local spec = require('org.config').opts.todo_keywords
  if type(spec) == 'table' then
    spec = spec[1]
  end
  local open, done, in_done = {}, {}, false
  for token in tostring(spec or ''):gmatch '%S+' do
    if token == '|' then
      -- the states after the bar are the done ones
      in_done = true
    else
      local word = token:match '^[%w_-]+'
      if word and word ~= '' then
        if in_done then
          done[#done + 1] = word
        else
          open[#open + 1] = word
        end
      end
    end
  end
  return { open = open, done = done }
end

local function handle(req, res)
  local path = req.path

  if req.method == 'GET' and path == '/' then
    res.send(200, 'text/html; charset=utf-8', page.dashboard())
    return
  end

  local asset = path:match '^/assets/([%w%._-]+)$'
  if req.method == 'GET' and asset then
    local body, mime = page.asset(asset)
    if body then
      res.send(200, mime, body)
      return
    end
    res.send(404, 'text/plain; charset=utf-8', 'no such asset')
    return
  end

  if req.method == 'GET' and path == '/roam' then
    res.send(200, 'text/html; charset=utf-8', page.roam())
    return
  end

  if req.method == 'GET' and path == '/events' then
    res.sse()
    return
  end

  if req.method == 'GET' and path == '/api/roam' then
    json(res, roam.payload())
    return
  end

  if req.method == 'GET' and path == '/api/roam/note' then
    local note, err = roam.note(req.query.id)
    json(res, { note = note, error = err })
    return
  end

  -- The card on the page is UI; what it needs from the machine -- a voice, a
  -- microphone, a tmux pane for the run -- lives in helpers/org/voice.lua.
  -- The click starts the conversation and returns at once (it takes as long
  -- as speaking and listening do); the page polls the state it draws.
  if req.method == 'GET' and path == '/api/voice' then
    json(res, require('helpers.org.voice').status())
    return
  end

  if req.method == 'POST' and path == '/api/voice' then
    local body = payload_of(req)
    if body.cancel then
      require('helpers.org.voice').cancel()
      json(res, require('helpers.org.voice').status())
      return
    end
    if body.stop then
      require('helpers.org.voice').stop()
      json(res, require('helpers.org.voice').status())
      return
    end
    -- the approve button under the words a listen ended on: from here they are
    -- the talking instance's, and the card says where they went
    if body.send then
      require('helpers.org.voice').send()
      json(res, require('helpers.org.voice').status())
      return
    end
    -- `entry` is what the list had highlighted: the words become a ticket under
    -- it, so the run starts pre-selected inside the project the page was on.
    -- `source` is the page's own microphone (`browser`) when it has one: the
    -- sound is then streamed up to /api/voice/audio rather than recorded here
    local started = require('helpers.org.voice').converse(body.view, body.entry, body.source)
    json(res, { started = started, status = require('helpers.org.voice').status() })
    return
  end

  -- A page recording with its own microphone streams the sound here, one piece
  -- at a time (assets/jarvis.js): the body is raw 16 kHz mono PCM, which is
  -- what the server would have recorded, so the level, the words so far and
  -- the transcription keep coming from /api/voice unchanged
  if req.method == 'POST' and path == '/api/voice/audio' then
    json(res, { bytes = require('helpers.org.voice').chunk(req.body) })
    return
  end

  if req.method == 'POST' and path == '/api/voice/say' then
    local body = payload_of(req)
    require('helpers.org.voice').say(body.text or '', body.entry)
    json(res, require('helpers.org.voice').status())
    return
  end

  if req.method == 'GET' and path == '/api/live' then
    local live = require 'helpers.org.web.live'
    local r = live.runs()
    local out = { generated = os.date '%Y-%m-%d %H:%M:%S', tickets = {}, sessions = {}, activity = {}, instances = {} }
    for id in pairs(r.tickets) do
      out.tickets[#out.tickets + 1] = id
    end
    for key in pairs(r.sessions) do
      out.sessions[#out.sessions + 1] = key
    end
    for _, key in ipairs(vim.list_extend(vim.list_slice(out.sessions), out.tickets)) do
      out.activity[key] = live.activity(key)
    end
    -- the Runs view's rows: the same list, one row per pane, with the ticket
    -- each run is on resolved back to its entry
    out.instances = require('helpers.org.web.data').instances()
    json(res, out)
    return
  end

  if req.method == 'GET' and path == '/api/live/stream' then
    local key = req.query.key or ''
    if not key:match '%S' then
      res.send(400, 'text/plain; charset=utf-8', 'no session key')
      return
    end
    res.sse()
    require('helpers.org.web.live').watch(key, res)
    return
  end

  if req.method == 'GET' and path == '/api/data' then
    local out = data.payload(req.query.file)
    out.keywords = keyword_lists()
    json(res, out)
    return
  end

  -- the states a page may offer, without walking the files
  -- the phone door: the ngrok address of this server and the QR of it
  if req.method == 'GET' and path == '/api/share' then
    json(res, share.payload())
    return
  end

  if req.method == 'POST' and path == '/api/share' then
    local body = payload_of(req)
    if body.on == false then
      share.stop()
    elseif state.port then
      share.start(state.port)
    end
    json(res, share.payload())
    return
  end

  if req.method == 'GET' and path == '/api/keywords' then
    json(res, { keywords = keyword_lists() })
    return
  end

  if req.method == 'GET' and path == '/api/entry' then
    local html, err = actions.entry_html {
      file = req.query.file,
      line = req.query.line,
      id = req.query.id,
    }
    -- the page's own heading, drawn again: a box ticked or a keyword changed
    -- in the body moves the entry's cookie, and the heading would keep the
    -- one it was loaded with
    local path_file = actions.agenda_path(req.query.file)
    local entry = path_file and data.find(path_file, tonumber(req.query.line), req.query.id) or nil
    json(res, { html = html, error = err, title = page.node_title(entry) })
    return
  end

  if req.method == 'POST' and path == '/api/state' then
    local body = payload_of(req)
    local new, err, warning = actions.set_state(body, body.state)
    data.invalidate()
    json(res, { state = new, error = err, warning = warning })
    return
  end

  -- the keyword of a headline drawn inside the entry's body ('NEXT' on a
  -- child heading), named by its place under the entry
  if req.method == 'POST' and path == '/api/header' then
    local body = payload_of(req)
    local out, err = actions.heading_state(body, body.heading, body.text, body.state)
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  -- one checkbox item of the entry's body, named by its place in the list
  if req.method == 'POST' and path == '/api/box' then
    local body = payload_of(req)
    local out, err = actions.box(body, body.box, body.text, body.on and true or false)
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'POST' and path == '/api/open' then
    local body = payload_of(req)
    local ok = actions.open(body)
    json(res, { ok = ok })
    return
  end

  if req.method == 'GET' and path == '/api/text' then
    local text, err = actions.text {
      file = req.query.file,
      line = req.query.line,
      id = req.query.id,
    }
    json(res, { text = text, error = err })
    return
  end

  if req.method == 'POST' and path == '/api/text' then
    local body = payload_of(req)
    local out, err = actions.write(body, body.lines)
    json(res, { text = out, error = err })
    return
  end

  if req.method == 'POST' and path == '/api/cycle' then
    local body = payload_of(req)
    local out, err = actions.cycle(body)
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'POST' and path == '/api/tags' then
    local body = payload_of(req)
    local out, err = actions.tags(body, body.tags or body.tag)
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'POST' and path == '/api/priority' then
    local body = payload_of(req)
    local out, err = actions.priority(body, body.priority or '')
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'POST' and path == '/api/archive' then
    local body = payload_of(req)
    local out, err = actions.archive(body)
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  -- the entry's own subtree, or -- with a `heading` -- the subtree of one
  -- headline drawn inside its body
  if req.method == 'POST' and path == '/api/kill' then
    local body = payload_of(req)
    local out, err
    if body.heading ~= nil then
      out, err = actions.heading_kill(body, body.heading, body.text)
    else
      out, err = actions.kill(body)
    end
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'POST' and path == '/api/undo' then
    local body = payload_of(req)
    local out, err = actions.undo(body)
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'POST' and path == '/api/refile' then
    local body = payload_of(req)
    local out, err = actions.refile(body, body.dest or {})
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'POST' and path == '/api/capture' then
    local body = payload_of(req)
    local out, err = actions.capture {
      file = body.file,
      line = body.line,
      id = body.id,
      title = body.title,
      body = body.body,
    }
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'POST' and path == '/api/note' then
    local body = payload_of(req)
    local out, err = actions.note(body, body.text)
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'POST' and path == '/api/launch' then
    local body = payload_of(req)
    local out, err = actions.launch(body, body.jump and true or false)
    json(res, vim.tbl_extend('force', { error = err }, out or {}))
    return
  end

  if req.method == 'GET' and path == '/preview' then
    local html, err = actions.entry_html {
      file = req.query.file,
      line = req.query.line,
      id = req.query.id,
    }
    local file = actions.agenda_path(req.query.file)
    if not file then
      res.send(404, 'text/plain; charset=utf-8', 'no such org file')
      return
    end
    res.send(
      200,
      'text/html; charset=utf-8',
      page.preview {
        file = file,
        line = tonumber(req.query.line),
        html = html,
        error = err,
        entry = data.find(file, tonumber(req.query.line), req.query.id),
      }
    )
    return
  end

  if req.method == 'GET' and path == '/file' then
    local out, err = actions.file(req.query.path)
    if not out then
      res.send(200, 'text/html; charset=utf-8', page.file { path = req.query.path or '', line = nil, error = err })
      return
    end
    local line = tonumber(req.query.line)
    local html = require('helpers.org.web.highlight').code(out.text, out.lang or '')
    res.send(200, 'text/html; charset=utf-8', page.file { path = out.path, line = line, lang = out.lang, inner = html, text = out.text })
    return
  end

  res.send(404, 'text/plain; charset=utf-8', 'not found')
end

--- Tell every open page that the vault changed. Debounced: one save raises
--- several events, and the pages only need the last one.
local function broadcast()
  if not state.server then
    return
  end
  if state.timer then
    return
  end
  state.timer = uv.new_timer()
  state.timer:start(120, 0, function()
    state.timer:stop()
    state.timer:close()
    state.timer = nil
    vim.schedule(function()
      data.invalidate()
      roam.invalidate()
      if state.server then
        state.server.broadcast('change', '{}')
      end
    end)
  end)
end

--- The modules a page's redraw can pick up without restarting nvim: the ones
--- that read the vault or draw it, and hold nothing between requests but a
--- cache. `init`, `http`, `live` and `share` keep state a reload would lose
--- (the server itself, the open streams, the runs being watched), so an edit
--- to one of them waits for the next start.
local RELOADABLE = {
  'actions',
  'clicks',
  'data',
  'headings',
  'highlight',
  'links',
  'markdown',
  'page',
  'qr',
  'roam',
  'turns',
}

--- Load the renderer modules again, all of them or none: a file with a syntax
--- error in it leaves the last good set serving the pages, and says so.
---@return boolean ok, string|nil err
local function reload_web()
  local saved = {}
  for _, name in ipairs(RELOADABLE) do
    local key = 'helpers.org.web.' .. name
    saved[key] = package.loaded[key]
    package.loaded[key] = nil
  end
  local ok, fresh = pcall(function()
    -- the table is built whole or not at all, so no caller is left holding
    -- half of a new set beside half of the old one
    return {
      actions = require 'helpers.org.web.actions',
      data = require 'helpers.org.web.data',
      page = require 'helpers.org.web.page',
      roam = require 'helpers.org.web.roam',
    }
  end)
  if not ok then
    for key, mod in pairs(saved) do
      package.loaded[key] = mod
    end
    return false, fresh
  end
  actions = fresh.actions
  data = fresh.data
  page = fresh.page
  roam = fresh.roam
  return true
end

--- The site's own files changed: reload what a page is drawn from, then tell
--- every open page to load itself again -- the asset it asks for next is read
--- from disk, so the browser shows the edit without a refresh.
---@param paths string[]
local function rebuilt(paths)
  local code = false
  for _, path in ipairs(paths) do
    if path:match '%.lua$' then
      code = true
      break
    end
  end
  if code then
    local ok, err = reload_web()
    if not ok then
      vim.notify('org web: ' .. tostring(err), vim.log.levels.WARN)
      return
    end
  end
  if state.server then
    state.server.broadcast('reload', '{}')
  end
end

--- The port every session listens on. Fixed, so a reload, a bookmark and a
--- tab left open across a restart of nvim all keep working; only a port
--- something else already holds falls back to one the system picks.
local PORT = 7313

local function start()
  if state.server then
    return state.server
  end
  local ok, server = pcall(http.listen, { host = '127.0.0.1', port = PORT }, handle)
  if not ok or not server then
    ok, server = pcall(http.listen, { host = '127.0.0.1', port = 0 }, handle)
    if ok and server then
      vim.notify(('org web: port %d is taken, listening on %d instead'):format(PORT, server.port), vim.log.levels.WARN)
    end
  end
  if not ok or not server then
    error('org web: could not start the server: ' .. tostring(server))
  end
  state.server = server
  state.port = server.port

  -- the vault on disk (an agent's write-back, an external edit)
  local cfg_ok, cfg = pcall(require, 'org.config')
  local root = (cfg_ok and cfg.opts and cfg.opts.org_directory) or '~/org'
  require('helpers.org.watch').subscribe(broadcast)

  -- edits made inside nvim, before they are written
  local group = vim.api.nvim_create_augroup('OrgWebViews', { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'BufWritePost' }, {
    group = group,
    pattern = '*.org',
    callback = broadcast,
  })
  -- the watcher needs the tree; the buffer events cover the file being
  -- edited, and both are cheap
  require('helpers.org.watch').start(root, broadcast)

  -- the site's own files, so an edit to an asset or a renderer module shows up
  -- in the open pages without a refresh
  state.hot = hot.start({ web_dir, web_dir .. '/assets' }, rebuilt)

  -- and the tunnel the phone reaches it through, unless `g:org_web_share` is
  -- off: it starts beside the server, so the address exists as soon as a page
  share.start(server.port, function(url)
    vim.notify('org web: on your phone at ' .. url, vim.log.levels.INFO)
  end)

  return state.server
end

--- Base URL of the running server, starting it on first use.
---@return string
function M.base()
  start()
  return string.format('http://127.0.0.1:%d', state.port)
end

--- URL of `path` on the running server.
---@param path string
---@return string
function M.url(path)
  return M.base() .. path
end

--- Hand `url` to the desktop's browser.
---
--- WSL has no X server, so `xdg-open` finds no browser there, and
--- `explorer.exe` takes the URL and does nothing with it. This is how
--- markdown-preview.nvim opens its page (its `lib/util/opener.js` treats a
--- Microsoft kernel as win32): the URL goes to the Windows shell through
--- `cmd.exe /c start`, with an empty window title, from a Windows-side
--- working directory (a UNC `cwd` makes cmd complain), and with `&` written
--- `^&` so a query string survives cmd's own parsing.
---@param url string
---@return boolean
local function open_url(url)
  local function run(cmd, opts)
    return pcall(vim.system, cmd, vim.tbl_extend('force', { detach = true }, opts or {}))
  end
  if vim.fn.executable 'wslview' == 1 then
    if run { 'wslview', url } then
      return true
    end
  end
  if is_wsl() and vim.fn.executable 'cmd.exe' == 1 then
    local cwd = vim.uv.fs_stat '/mnt/c' and '/mnt/c' or nil
    if run({ 'cmd.exe', '/c', 'start', '""', (url:gsub('&', '^&')) }, { cwd = cwd }) then
      return true
    end
  end
  local ok, _, err = pcall(vim.ui.open, url)
  if ok then
    return true
  end
  vim.notify('org web: could not open a browser: ' .. tostring(err), vim.log.levels.WARN)
  return false
end

M.open_url = open_url

--- Open the dashboard in the browser (the `:OrgWeb` command, `<leader>ob`).
---@return string url
function M.dashboard()
  local url = M.url '/'
  open_url(url)
  return url
end

--- Render the node at the cursor (or `lnum`) in the browser (`:OrgPreview`,
--- `O` in an org buffer). A cursor above every headline renders the whole
--- file.
---@param bufnr? integer
---@param lnum? integer
---@return string|nil url
function M.preview(bufnr, lnum)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then
    vim.notify('org web: this buffer has no file', vim.log.levels.WARN)
    return nil
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
  local line = lnum
  if not line then
    local pos = vim.api.nvim_win_get_cursor(0)[1]
    local ok, file = pcall(require('org.files').get_buffer, bufnr)
    local hl = ok and file and file:headline_at(pos) or nil
    line = hl and hl.line or nil
  end
  local query = 'file=' .. encode(path)
  if line then
    query = query .. '&line=' .. line
  end
  local url = M.url('/preview?' .. query)
  open_url(url)
  return url
end

--- Open the roam mode in the browser (the `:OrgRoam` command): the notes
--- under the roam directory, each rendered with its links, and the graph of
--- the links between them.
---@return string url
function M.roam()
  local url = M.url '/roam'
  open_url(url)
  return url
end

--- Read the site's own files again in a server that is already running: the
--- renderer modules come off disk anew, the page watcher is restarted, and
--- every open page is told to load itself again. The server itself and the
--- phone's tunnel stay where they are, so the address on the phone is the same
--- one after this (`:OrgWebReload`).
---@return boolean ok, string|nil err
function M.reload()
  if not state.server then
    start()
    return true
  end
  local ok, err = reload_web()
  if not ok then
    return false, err
  end
  if state.hot then
    state.hot()
  end
  state.hot = hot.start({ web_dir, web_dir .. '/assets' }, rebuilt)
  state.server.broadcast('reload', '{}')
  return true
end

--- Put the dashboard on a public address and hand it over: the ngrok URL is
--- copied and the page that draws its QR opens in the browser (the
--- `:OrgWebShare` command). Wait a moment for the agent to come up.
---@return string|nil url
function M.share()
  local url = M.url '/'
  start()
  local deadline = uv.now() + 8000
  while not share.url() and uv.now() < deadline do
    vim.wait(100)
  end
  local public = share.url()
  if public then
    pcall(vim.fn.setreg, '+', public)
    vim.notify('org web: on your phone at ' .. public .. ' (copied)', vim.log.levels.INFO)
  else
    local payload = share.payload()
    vim.notify('org web: no public address yet (' .. tostring(payload.error or payload.status) .. ')', vim.log.levels.WARN)
  end
  open_url(url)
  return public
end

--- Stop the server and drop the watchers.
function M.stop()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  if state.hot then
    state.hot()
    state.hot = nil
  end
  pcall(vim.api.nvim_del_augroup_by_name, 'OrgWebViews')
  require('helpers.org.watch').unsubscribe(broadcast)
  require('helpers.org.web.live').stop()
  share.stop()
  if state.server then
    state.server.stop()
  end
  state.server = nil
  state.port = nil
end

return M
