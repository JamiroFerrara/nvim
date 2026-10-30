-- The phone door: an ngrok tunnel in front of the org web server, and the QR
-- code of its address.
--
-- `ngrok http <port>` is started next to the server and its address read off
-- the agent's own log (the `started tunnel` line) rather than off the
-- inspector on port 4040: a second ngrok on the machine pushes the inspector
-- to another port, and a tunnel needs none of it. The address is random and
-- changes with every run, so it is kept for the life of the tunnel and the QR
-- is drawn from it (helpers/org/web/qr.lua).
--
-- The door also goes down when the network under it goes: the agent loses its
-- session (`heartbeat timeout, terminating session` is one way it says so),
-- the address dies with it, and a tunnel nothing starts again leaves the page
-- saying there is no public address and drawing no code. An error in the log
-- is therefore the address going away, not a verdict -- the agent retries on
-- its own, and when the agent itself dies the next one is started after a
-- short wait, for as long as the door is wanted.
local M = {}

local uv = vim.uv or vim.loop
local qr = require 'helpers.org.web.qr'

--- How long to wait before each attempt to bring a dead agent back, in
--- milliseconds. The last one repeats, so the door keeps trying.
local RETRY_MS = { 1000, 2000, 5000, 10000, 20000, 30000 }

local state = {
  job = nil,
  url = nil,
  svg = nil,
  status = 'off', -- off | starting | up | error
  err = nil,
  port = nil,
  want = false, -- the door is wanted open: an agent belongs running
  on_up = nil, -- told about every address, a new one after each reconnect
  tries = 0, -- agents started since the last address
  retry = nil, -- the timer waiting to start the next one
}

local function set(status, err)
  state.status = status
  state.err = err
end

local function forget()
  state.url = nil
  state.svg = nil
end

local function cancel_retry()
  local timer = state.retry
  state.retry = nil
  if timer then
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
  end
end

local start -- the agent starter, defined below the retry timer that calls it

--- Start a fresh agent after a wait, unless the door closed meanwhile.
local function schedule()
  local port = state.port
  if not state.want or state.job or state.retry or not port then
    return
  end
  local delay = RETRY_MS[math.min(state.tries + 1, #RETRY_MS)]
  state.tries = state.tries + 1
  local timer = uv.new_timer()
  state.retry = timer
  timer:start(delay, 0, function()
    vim.schedule(function()
      if state.retry ~= timer then
        return
      end
      cancel_retry()
      if not state.want or state.job then
        return
      end
      start(port)
    end)
  end)
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
local function handle_line(line)
  local ok, decoded = pcall(vim.json.decode, line)
  if not ok or type(decoded) ~= 'table' then
    return
  end
  if decoded.msg == 'started tunnel' and type(decoded.url) == 'string' then
    state.url = decoded.url
    state.svg = qr.svg(decoded.url, { size = 200, level = 'M', title = 'org on your phone' })
    state.tries = 0
    set('up', nil)
    local on_up = state.on_up
    if on_up then
      on_up(state.url)
    end
  elseif decoded.lvl == 'eror' or decoded.lvl == 'error' then
    -- The agent is still alive and reconnecting, so the door is not lost --
    -- but the address went with the session, and a code drawn for it would
    -- open nothing. A new address arrives as a fresh `started tunnel` line.
    forget()
    set('starting', decoded.err or decoded.msg or 'ngrok is reconnecting')
  end
end

--- Start one agent. Called again by the retry timer when it dies.
start = function(port)
  if vim.fn.executable 'ngrok' ~= 1 then
    set('error', 'ngrok is not on the PATH')
    return false
  end
  state.port = port
  forget()
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
            if state.job ~= job then
              return
            end
            handle_line(line)
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
        forget()
        if not state.want then
          set('off', nil)
          return
        end
        -- what the agent said on its way out, or the last thing it logged
        -- when it said nothing there
        local why = vim.trim(tail or '')
        if why == '' and state.err then
          why = state.err
        end
        set('starting', why ~= '' and ('ngrok exited (%s) %s'):format(obj.code, why) or ('ngrok exited (%s)'):format(obj.code))
        schedule()
      end)
    end)
  end)
  if not ok or not job then
    set('error', tostring(err))
    schedule()
    return false
  end
  state.job = job
  return true
end

--- Start the tunnel to `port`, if it is wanted and not already up.
---@param port integer
---@param on_up? fun(url: string)
---@return boolean started
function M.start(port, on_up)
  if on_up then
    state.on_up = on_up
  end
  if not allowed() then
    M.stop()
    set('off', nil)
    return false
  end
  state.want = true
  if state.port ~= port then
    -- a new server means a new tunnel, and the old agent has nothing to serve
    cancel_retry()
    local job = state.job
    state.job = nil
    if job then
      pcall(job.kill, job, 'sigterm')
    end
    state.tries = 0
  elseif state.status == 'up' or state.job or state.retry then
    return state.status == 'up'
  end
  state.port = port
  return start(port)
end

--- Stop the tunnel, forget the address, and stop bringing it back.
function M.stop()
  state.want = false
  state.on_up = nil
  cancel_retry()
  local job = state.job
  state.job = nil
  state.port = nil
  state.tries = 0
  forget()
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
    retrying = state.retry ~= nil,
  }
end

--- The public address, once there is one.
---@return string|nil
function M.url()
  return state.url
end

return M
