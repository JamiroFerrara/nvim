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
-- refetches. The server listens on the loopback address only, the way
-- markdown-preview.nvim's does.
local M = {}

local actions = require 'helpers.org.web.actions'
local data = require 'helpers.org.web.data'
local http = require 'helpers.org.web.http'
local page = require 'helpers.org.web.page'

local state = {
  server = nil,
  port = nil,
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

  if req.method == 'POST' and path == '/api/kill' then
    local body = payload_of(req)
    local out, err = actions.kill(body)
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
    res.send(200, 'text/html; charset=utf-8', page.preview {
      file = file,
      line = tonumber(req.query.line),
      html = html,
      error = err,
      entry = data.find(file, tonumber(req.query.line), req.query.id),
    })
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
  local ok, server = pcall(http.listen, { host = '127.0.0.1', port = 0 }, handle)
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
end

return M
