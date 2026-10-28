-- A small HTTP/1.1 server on top of libuv, for the org browser views
-- (helpers/org/web/init.lua). One listener, a fresh connection per request
-- (`Connection: close`), and server-sent events for the pages that have to
-- follow the vault as it changes.
--
-- Everything a route handler touches is nvim state, so the handler runs
-- through `vim.schedule`: libuv callbacks are fast events, where the API is
-- not allowed.
local M = {}

local uv = vim.uv or vim.loop

local REASONS = {
  [200] = 'OK',
  [302] = 'Found',
  [400] = 'Bad Request',
  [403] = 'Forbidden',
  [404] = 'Not Found',
  [500] = 'Internal Server Error',
}

local function decode(text)
  return (text:gsub('%+', ' '):gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

--- The query half of a request target as a flat table.
---@param query string|nil
---@return table<string, string>
local function parse_query(query)
  local out = {}
  for pair in (query or ''):gmatch '[^&]+' do
    local key, value = pair:match '^([^=]*)=(.*)$'
    out[decode(key or pair)] = decode(value or '')
  end
  return out
end

--- Wrap one accepted socket: parse the request, then either one buffered
--- reply or an open event stream.
---@param sock table libuv tcp handle
---@param handler fun(req: table, res: table)
---@param register fun(res: table) keep the connection in the broadcast list
local function serve(sock, handler, register)
  local buf, parsed, length = '', nil, 0
  local replied, streaming, closed = false, false, false
  local res = { events = {} }

  local function close()
    if closed then
      return
    end
    closed = true
    pcall(function()
      sock:read_stop()
    end)
    pcall(function()
      sock:close()
    end)
  end

  res.close = close

  function res.send(status, ctype, body, extra)
    if replied then
      return
    end
    replied = true
    body = body or ''
    local head = {
      ('HTTP/1.1 %d %s'):format(status, REASONS[status] or 'Error'),
      'Content-Type: ' .. (ctype or 'text/plain; charset=utf-8'),
      'Content-Length: ' .. #body,
      'Cache-Control: no-store',
      'Connection: close',
    }
    for _, line in ipairs(extra or {}) do
      head[#head + 1] = line
    end
    head[#head + 1] = ''
    head[#head + 1] = ''
    sock:write(table.concat(head, '\r\n') .. body, function()
      pcall(function()
        sock:shutdown(function()
          close()
        end)
      end)
    end)
  end

  --- Switch the connection to a server-sent events stream.
  function res.sse()
    if replied then
      return
    end
    replied = true
    streaming = true
    register(res)
    sock:write(table.concat({
      'HTTP/1.1 200 OK',
      'Content-Type: text/event-stream; charset=utf-8',
      'Cache-Control: no-cache',
      'Connection: keep-alive',
      '',
      ': connected',
      '',
      '',
    }, '\r\n'))
  end

  function res.event(event, data)
    if not streaming or closed then
      return false
    end
    return pcall(function()
      sock:write('event: ' .. event .. '\nretry: 2000\ndata: ' .. (data or '{}') .. '\n\n')
    end)
  end

  res.is_streaming = function()
    return streaming
  end

  local function dispatch(req)
    local ok, err = pcall(handler, req, res)
    if not ok then
      if not replied then
        res.send(500, 'text/plain; charset=utf-8', 'handler error: ' .. tostring(err))
      end
      vim.notify('org web: ' .. tostring(err), vim.log.levels.WARN)
      return
    end
    if not replied then
      res.send(404, 'text/plain; charset=utf-8', 'not found')
    end
  end

  local function on_read(err, data)
    if closed then
      return
    end
    if err or not data then
      close()
      return
    end
    buf = buf .. data
    if not parsed then
      local at = buf:find('\r\n\r\n', 1, true)
      if not at then
        return
      end
      local head = buf:sub(1, at - 1)
      local first = head:match '^([^\r\n]*)'
      local method, target = first:match '^(%u+)%s+(%S+)'
      if not method then
        res.send(400, 'text/plain; charset=utf-8', 'bad request line')
        return
      end
      local path, query = target:match '^([^?]*)%??(.*)$'
      local headers = {}
      for line in head:gmatch '[^\r\n]+' do
        local key, value = line:match '^([^:]+):%s*(.*)$'
        if key then
          headers[key:lower()] = value
        end
      end
      length = tonumber(headers['content-length'] or '') or 0
      if length > 1024 * 1024 then
        res.send(400, 'text/plain; charset=utf-8', 'request body too large')
        return
      end
      parsed = {
        method = method,
        path = path == '' and '/' or decode(path),
        target = target,
        query = parse_query(query),
        headers = headers,
      }
      buf = buf:sub(at + 4)
    end
    if #buf < length then
      return
    end
    local req = parsed
    req.body = buf:sub(1, length)
    parsed = nil
    vim.schedule(function()
      dispatch(req)
    end)
  end

  sock:read_start(function(err, data)
    local ok, failure = pcall(on_read, err, data)
    if not ok then
      vim.notify('org web: ' .. tostring(failure), vim.log.levels.WARN)
      close()
    end
  end)
end

--- Start a server. `handler(req, res)` gets `req = { method, path, query,
--- headers, body }` and `res = { send, sse, event, close }`; a handler that
--- calls `res.sse()` keeps the socket open.
---@param opts { host?: string, port?: number }
---@param handler fun(req: table, res: table)
---@return table|nil server { port, broadcast, stop }
function M.listen(opts, handler)
  opts = opts or {}
  local sock = uv.new_tcp()
  if not sock then
    return nil
  end
  local ok, err = sock:bind(opts.host or '127.0.0.1', opts.port or 0)
  if not ok then
    sock:close()
    error(err)
  end
  local port = sock:getsockname().port

  local streams = {}
  local alive = true
  local server = { port = port }

  sock:listen(64, function(listen_err)
    if listen_err or not alive then
      return
    end
    local client = uv.new_tcp()
    if not client then
      return
    end
    local ok_accept = pcall(function()
      sock:accept(client)
    end)
    if not ok_accept then
      client:close()
      return
    end
    serve(client, handler, function(res)
      streams[#streams + 1] = res
    end)
  end)

  --- Send `data` to every open event stream; dead sockets drop out.
  ---@param event string
  ---@param data string|nil
  function server.broadcast(event, data)
    local keep = {}
    for _, conn in ipairs(streams) do
      if conn.event(event, data) then
        keep[#keep + 1] = conn
      end
    end
    streams = keep
  end

  function server.stop()
    alive = false
    for _, conn in ipairs(streams) do
      conn.close()
    end
    streams = {}
    pcall(function()
      sock:close()
    end)
  end

  return server
end

return M
