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
-- refetches. The server binds 0.0.0.0 under WSL, where a Windows browser
-- cannot reach a socket bound to Linux loopback; every request then has to
-- carry the token minted at startup (a cookie, or `?token=` on the URL
-- opened), so the LAN cannot read the vault off that port.
local M = {}

local actions = require 'helpers.org.web.actions'
local data = require 'helpers.org.web.data'
local http = require 'helpers.org.web.http'
local page = require 'helpers.org.web.page'

local state = {
  server = nil,
  port = nil,
  token = nil,
  timer = nil,
}

local uv = vim.uv or vim.loop

local function is_wsl()
  if vim.env.WSL_DISTRO_NAME and vim.env.WSL_DISTRO_NAME ~= '' then
    return true
  end
  local release = uv.os_uname().release or ''
  return release:lower():find('microsoft', 1, true) ~= nil
end

local function mint_token()
  local raw = uv.random(18)
  return (raw:gsub('.', function(char)
    return string.format('%02x', char:byte())
  end))
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

--- The request carried the startup token: either in the cookie a page sets
--- on its first load, or as `?token=` on the URL nvim opened.
---@param req table
---@return boolean
local function authorized(req)
  local token = state.token
  if not token then
    return false
  end
  if req.query.token == token then
    return true
  end
  local cookie = req.headers.cookie or ''
  return cookie:find('orgweb=' .. token, 1, true) ~= nil
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
  if not authorized(req) then
    res.send(403, 'text/plain; charset=utf-8', 'forbidden: reopen the view from nvim')
    return
  end
  local extra = { 'Set-Cookie: orgweb=' .. state.token .. '; Path=/; SameSite=Strict' }
  local path = req.path

  if req.method == 'GET' and path == '/' then
    res.send(200, 'text/html; charset=utf-8', page.dashboard(), extra)
    return
  end

  local asset = path:match '^/assets/([%w%._-]+)$'
  if req.method == 'GET' and asset then
    local body, mime = page.asset(asset)
    if body then
      res.send(200, mime, body, extra)
      return
    end
    res.send(404, 'text/plain; charset=utf-8', 'no such asset')
    return
  end

  if req.method == 'GET' and path == '/events' then
    res.sse()
    return
  end

  if req.method == 'GET' and path == '/api/data' then
    local out = data.payload(req.query.file)
    out.keywords = keyword_lists()
    json(res, out)
    return
  end

  if req.method == 'GET' and path == '/api/entry' then
    local html, err = actions.entry_html {
      file = req.query.file,
      line = req.query.line,
      id = req.query.id,
    }
    json(res, { html = html, error = err })
    return
  end

  if req.method == 'POST' and path == '/api/state' then
    local body = payload_of(req)
    local new, err, warning = actions.set_state(body, body.state)
    data.invalidate()
    json(res, { state = new, error = err, warning = warning })
    return
  end

  if req.method == 'POST' and path == '/api/open' then
    local body = payload_of(req)
    local ok = actions.open(body)
    json(res, { ok = ok })
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
    res.send(200, 'text/html; charset=utf-8', page.preview {
      file = file,
      line = tonumber(req.query.line),
      html = html,
      error = err,
      entry = data.find(file, tonumber(req.query.line), req.query.id),
    }, extra)
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
      if state.server then
        state.server.broadcast('change', '{}')
      end
    end)
  end)
end

local function start()
  if state.server then
    return state.server
  end
  state.token = mint_token()
  local host = is_wsl() and '0.0.0.0' or '127.0.0.1'
  local ok, server = pcall(http.listen, { host = host, port = 0 }, handle)
  if not ok or not server then
    state.token = nil
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

  return state.server
end

--- Base URL of the running server, starting it on first use.
---@return string
function M.base()
  start()
  return string.format('http://127.0.0.1:%d', state.port)
end

--- URL of `path` on the running server, carrying the startup token.
---@param path string
---@return string
function M.url(path)
  local url = M.base() .. path
  return url .. (path:find('?', 1, true) and '&' or '?') .. 'token=' .. state.token
end

local function open_url(url)
  local function run(cmd)
    local ok = pcall(vim.system, cmd, { detach = true })
    return ok
  end
  if vim.fn.executable 'wslview' == 1 then
    if run { 'wslview', url } then
      return true
    end
  end
  if is_wsl() and vim.fn.executable 'explorer.exe' == 1 then
    if run { 'explorer.exe', url } then
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

--- Stop the server and drop the watchers.
function M.stop()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  pcall(vim.api.nvim_del_augroup_by_name, 'OrgWebViews')
  require('helpers.org.watch').unsubscribe(broadcast)
  if state.server then
    state.server.stop()
  end
  state.server = nil
  state.port = nil
  state.token = nil
end

return M
