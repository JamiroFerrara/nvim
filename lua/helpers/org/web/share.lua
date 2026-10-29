-- The phone door: an ngrok tunnel in front of the org web server, and the QR
-- code of its address.
--
-- `ngrok http <port>` is started next to the server and its address read off
-- the agent's own log (the `started tunnel` line) rather than off the
-- inspector on port 4040: a second ngrok on the machine pushes the inspector
-- to another port, and a tunnel needs none of it. The address is random and
-- changes with every run, so it is kept for the life of the tunnel and the QR
-- is drawn from it (helpers/org/web/qr.lua).
local M = {}

local uv = vim.uv or vim.loop
local qr = require 'helpers.org.web.qr'

local state = {
  job = nil,
  url = nil,
  svg = nil,
  status = 'off', -- off | starting | up | error
  err = nil,
  port = nil,
}

local function set(status, err)
  state.status = status
  state.err = err
end

-- The agent is a child of this nvim, and a headless run that quits leaves it
-- behind: take it down with the editor.
vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('OrgWebShare', { clear = true }),
  callback = function()
    M.stop()
  end,
})

--- Whether a run may put the vault on a public address at all:
--- `g:org_web_share = false` keeps it local.
local function allowed()
  return vim.g.org_web_share ~= false
end

--- One line of the agent's log: `value` is the parsed JSON, `ok` says whether
--- it parsed at all.
local function handle_line(line, on_up)
  local ok, decoded = pcall(vim.json.decode, line)
  if not ok or type(decoded) ~= 'table' then
    return
  end
  if decoded.msg == 'started tunnel' and type(decoded.url) == 'string' then
    state.url = decoded.url
    state.svg = qr.svg(decoded.url, { size = 200, level = 'M', title = 'org on your phone' })
    set('up', nil)
    if on_up then
      on_up(state.url)
    end
  elseif decoded.lvl == 'eror' or decoded.lvl == 'error' then
    set('error', decoded.err or decoded.msg or 'ngrok failed')
  end
end

--- Start the tunnel to `port`, if it is wanted and not already up.
---@param port integer
---@param on_up? fun(url: string)
---@return boolean started
function M.start(port, on_up)
  if state.status == 'up' and state.port == port then
    return true
  end
  if state.job then
    M.stop()
  end
  if not allowed() then
    set('off', nil)
    return false
  end
  if vim.fn.executable 'ngrok' ~= 1 then
    set('error', 'ngrok is not on the PATH')
    return false
  end
  state.port = port
  state.url = nil
  state.svg = nil
  set('starting', nil)

  local pending = ''
  local tail = ''
  local job
  local ok, err = pcall(function()
    job = vim.system({
      'ngrok',
      'http',
      '127.0.0.1:' .. port,
      '--log=stdout',
      '--log-format=json',
      '--inspect=false',
    }, {
      text = true,
      stdout = function(_, data)
        if not data then
          return
        end
        pending = pending .. data
        while true do
          local line, rest = pending:match '^([^\n]*)\n(.*)$'
          if not line then
            break
          end
          pending = rest
          vim.schedule(function()
            handle_line(line, on_up)
          end)
        end
      end,
      stderr = function(_, data)
        if data and data:match '%S' then
          tail = data
        end
      end,
    }, function(obj)
      vim.schedule(function()
        if state.job ~= job then
          return
        end
        state.job = nil
        state.url = nil
        state.svg = nil
        if state.status == 'up' or state.status == 'starting' then
          set('error', ('ngrok exited (%s) %s'):format(obj.code, tail or ''))
        end
      end)
    end)
  end)
  if not ok or not job then
    set('error', tostring(err))
    return false
  end
  state.job = job
  return true
end

--- Stop the tunnel and forget the address.
function M.stop()
  local job = state.job
  state.job = nil
  state.url = nil
  state.svg = nil
  state.port = nil
  set('off', nil)
  if job then
    pcall(job.kill, job, 'sigterm')
  end
end

--- What the page draws: the state of the tunnel, its address and the QR of
--- that address.
function M.payload()
  return {
    status = state.status,
    url = state.url,
    qr = state.svg,
    error = state.err,
    port = state.port,
  }
end

--- The public address, once there is one.
---@return string|nil
function M.url()
  return state.url
end

return M
