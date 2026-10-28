-- The runs in flight, as the browser views show them (helpers/org/web).
--
-- An omp run records every step of its work in a session transcript under the
-- agent directory: one JSON object per line, appended as it happens, in the
-- directory `helpers/org/ai.lua`'s `session_dir` names for the ticket's
-- :OMP_SESSION:. Tailing that file is what puts a running instance on the
-- page -- the text the agent is saying, the tool it just started, what came
-- back -- without the page having to reach into the tmux pane.
--
-- Which tickets are running is the launcher's own mark: the pane it opened
-- carries the ticket's :ID: in `@omp_ticket` (or the session key in
-- `@omp_orchestrator` for a batch's orchestrator). One `tmux list-panes`
-- answers that for the whole dashboard, and it is cached for a moment,
-- because the page asks on every refresh.
--
-- A stream (`M.watch`) is a server-sent events connection the page opens on
-- one ticket: a snapshot of the transcript's tail, then each new line as the
-- run writes it, then the run's state when it changes.
local M = {}

local uv = vim.uv or vim.loop

local TICK = 250 -- ms between the watchers' looks at the transcripts
local RUNS_TTL = 2000 -- ms a `tmux list-panes` answer is reused
local HEARTBEAT = 15000 -- ms of silence before a stream says it is alive
local TAIL_BYTES = 256 * 1024 -- how far back a first look reads
local CHUNK_BYTES = 96 * 1024 -- one tick reads at most this much
local BACKLOG = 200 -- events a stream's snapshot carries
local ACTIVITY_BYTES = 16 * 1024 -- how far back the list's one-line summary reads

local runs = { at = 0, tickets = {}, sessions = {} }
local watchers = {}
local timer = nil

--- The transcript directory of a ticket's run: ai.lua's rule, so a page and
--- the launcher never disagree about where a session lives.
---@param key string
---@return string
local function session_dir(key)
  return require('helpers.org.ai').session_dir(key)
end

--- Every running instance: the tickets a pane is marked with, and the session
--- keys a batch's orchestrator pane carries. Cached briefly, and refreshed
--- from tmux when the cache is older than `RUNS_TTL`; with no tmux (or no
--- server) the answer is simply nothing running.
---@return { tickets: table<string, string>, sessions: table<string, string> }
function M.runs()
  local now = uv.now()
  if now - runs.at < RUNS_TTL then
    return runs
  end
  runs.at = now
  runs.tickets, runs.sessions = {}, {}
  if vim.fn.executable 'tmux' ~= 1 then
    return runs
  end
  local out = vim.fn.system {
    'tmux',
    'list-panes',
    '-a',
    '-F',
    '#{pane_id}\t#{@omp_ticket}\t#{@omp_orchestrator}\t#{pane_dead}',
  }
  if vim.v.shell_error ~= 0 then
    return runs
  end
  for line in vim.gsplit(out or '', '\n', { plain = true }) do
    local pane, ticket, key, dead = line:match '^(%%%d+)\t([^\t]*)\t([^\t]*)\t(%d)$'
    if pane and dead == '0' then
      if ticket and ticket ~= '' then
        runs.tickets[ticket] = pane
      end
      if key and key ~= '' then
        runs.sessions[key] = pane
      end
    end
  end
  return runs
end

--- The pane running `key` (a ticket's :ID: or a session key), or nil.
---@param key string
---@return string|nil
function M.pane(key)
  local r = M.runs()
  return r.tickets[key] or r.sessions[key]
end

--- The newest transcript of `key`'s session: a resumed run writes a new file
--- beside the old ones, and the page wants the one being written now.
---@param key string
---@return string|nil path, integer|nil mtime
function M.file(key)
  local dir = session_dir(key)
  local newest, newest_at = nil, -1
  local ok, scan = pcall(uv.fs_scandir, dir)
  if not ok or not scan then
    return nil
  end
  while true do
    local name, kind = uv.fs_scandir_next(scan)
    if not name then
      break
    end
    if (kind == 'file' or kind == nil) and name:match '%.jsonl$' then
      local stat = uv.fs_stat(dir .. '/' .. name)
      if stat and (stat.mtime.sec + stat.mtime.nsec / 1e9) > newest_at then
        newest, newest_at = dir .. '/' .. name, stat.mtime.sec
      end
    end
  end
  return newest
end

--- Read `path` from byte `offset`, at most `max` bytes.
---@param path string
---@param offset integer
---@param max integer
---@return string|nil blob, integer|nil next_offset, integer|nil size
local function read_at(path, offset, max)
  local stat = uv.fs_stat(path)
  if not stat then
    return nil
  end
  if offset >= stat.size then
    return '', offset, stat.size
  end
  local fd = uv.fs_open(path, 'r', 0)
  if not fd then
    return nil
  end
  local out, pos, want = {}, offset, math.min(max, stat.size - offset)
  while pos < offset + want do
    local data = uv.fs_read(fd, math.min(CHUNK_BYTES, offset + want - pos), pos)
    if not data or data == '' then
      break
    end
    out[#out + 1] = data
    pos = pos + #data
  end
  uv.fs_close(fd)
  return table.concat(out), pos, stat.size
end

--- Split `blob` into whole lines; the second value is the bytes they cover,
--- so the caller can keep a half-written last line for the next look.
---@param blob string
---@return string[] lines, integer used
local function whole_lines(blob)
  local lines, start = {}, 1
  while true do
    local nl = blob:find('\n', start, true)
    if not nl then
      break
    end
    lines[#lines + 1] = blob:sub(start, nl - 1)
    start = nl + 1
  end
  return lines, start - 1
end

--- One line of prose, clipped to `n` characters.
---@param text string|nil
---@param n integer
---@return string
local function clip(text, n)
  local flat = (tostring(text or ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
  if vim.fn.strchars(flat) > n then
    return (vim.fn.strcharpart(flat, 0, n - 1)) .. '…'
  end
  return flat
end

--- What a tool call was for, in one line: the intent the agent gave it, then
--- the argument that says what it works on.
---@param args table|nil
---@return string
local function detail(args)
  args = type(args) == 'table' and args or {}
  local hint = args.i or args.description or args.intent
  local target = args.command or args.path or args.pattern or args.query or args.file or args.url or args.prompt
  if type(hint) == 'table' then
    hint = nil
  end
  if type(target) == 'table' then
    target = nil
  end
  if hint and target then
    return clip(hint, 90) .. ' › ' .. clip(target, 120)
  end
  if hint then
    return clip(hint, 160)
  end
  if target then
    return clip(target, 180)
  end
  local keys, parts = {}, {}
  for key, value in pairs(args) do
    if type(value) ~= 'table' then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  for i = 1, math.min(#keys, 3) do
    parts[#parts + 1] = keys[i] .. '=' .. clip(args[keys[i]], 40)
  end
  return clip(table.concat(parts, ' '), 180)
end

--- The parts of a message record's content, as the events the page draws.
---@param record table
---@param out table[]
local function message_events(record, out)
  local message = record.message or {}
  local role = message.role
  local at = record.timestamp
  local content = type(message.content) == 'table' and message.content or {}
  if role == 'assistant' then
    for _, part in ipairs(content) do
      local kind = part.type
      if kind == 'text' and part.text and part.text:match '%S' then
        out[#out + 1] = { k = 'say', t = clip(part.text, 4000), at = at }
      elseif kind == 'thinking' and (part.text or part.thinking) then
        out[#out + 1] = { k = 'think', t = clip(part.text or part.thinking, 1200), at = at }
      elseif kind == 'toolCall' then
        out[#out + 1] = { k = 'tool', n = part.name or 'tool', t = detail(part.arguments), at = at }
      end
    end
    return
  end
  if role == 'toolResult' then
    local text = {}
    for _, part in ipairs(content) do
      if part.type == 'text' then
        text[#text + 1] = part.text or ''
      end
    end
    out[#out + 1] = {
      k = 'result',
      n = message.toolName,
      e = message.isError and true or false,
      t = clip(table.concat(text, '\n'), 900),
      at = at,
    }
    return
  end
  if role == 'user' then
    local text = {}
    for _, part in ipairs(content) do
      if part.type == 'text' then
        text[#text + 1] = part.text or ''
      end
    end
    if #text > 0 then
      out[#out + 1] = { k = 'user', t = clip(table.concat(text, '\n'), 1600), at = at }
    end
  end
end

--- The page's events for one transcript line: the agent's words, its tools,
--- what came back, and the title the run gave itself. A line it cannot read
--- (a half-written one, a record that is not a message) is simply not there.
---@param line string
---@param out table[]
local function parse(line, out)
  if line == '' then
    return
  end
  local ok, record = pcall(vim.json.decode, line)
  if not ok or type(record) ~= 'table' then
    return
  end
  if record.type == 'title' and record.title then
    out[#out + 1] = { k = 'title', t = clip(record.title, 140) }
  elseif record.type == 'message' then
    message_events(record, out)
  end
end

--- Parse whole lines into events.
---@param lines string[]
---@return table[]
local function events(lines)
  local out = {}
  for _, line in ipairs(lines) do
    parse(line, out)
  end
  return out
end

--- The transcript's tail as a first look: the last `BACKLOG` events, and the
--- byte offset a following read resumes from (the end of the last whole line,
--- so a half-written one is read again once it is complete).
---@param key string
---@param bytes integer|nil how far back to read (default: the stream's tail)
---@return table out { file, offset, size, events, running, title }
function M.snapshot(key, bytes)
  local out = { file = nil, offset = 0, size = 0, events = {}, running = M.pane(key) ~= nil, key = key }
  local path = M.file(key)
  if not path then
    return out
  end
  local stat = uv.fs_stat(path)
  local size = stat and stat.size or 0
  local start = math.max(0, size - (bytes or TAIL_BYTES))
  local blob, _, real = read_at(path, start, bytes or TAIL_BYTES)
  if not blob then
    return out
  end
  if start > 0 then
    -- the first line of a window that starts mid-file is a fragment of one
    local nl = blob:find('\n', 1, true)
    blob = nl and blob:sub(nl + 1) or ''
  end
  local lines, used = whole_lines(blob)
  local all = events(lines)
  out.file = path
  out.size = real or size
  out.offset = (real or size) - #blob + used
  out.events = vim.list_slice(all, math.max(1, #all - BACKLOG + 1), #all)
  for _, event in ipairs(out.events) do
    if event.k == 'title' then
      out.title = event.t
    end
  end
  return out
end

--- The last thing the run said or reached for, in one line: what the
--- dashboard's list shows under a running entry.
---@param key string
---@return string|nil
function M.activity(key)
  -- the last step only: a step's own line is in the tail's last few bytes
  local snap = M.snapshot(key, ACTIVITY_BYTES)
  for i = #snap.events, 1, -1 do
    local event = snap.events[i]
    if event.k == 'say' then
      return clip(event.t, 140)
    elseif event.k == 'tool' then
      return '→ ' .. (event.n or 'tool') .. (event.t ~= '' and (' ' .. event.t) or '')
    elseif event.k == 'think' then
      return '… ' .. clip(event.t, 120)
    end
  end
  return nil
end

--- The snapshot event of a first look (and of a resumed session's newer
--- transcript): the file the stream follows and the events it starts from.
---@param snap table
---@return string
local function frame(snap)
  return vim.json.encode {
    file = snap.file,
    offset = snap.offset,
    size = snap.size,
    running = snap.running,
    title = snap.title,
    events = snap.events,
  }
end

--- Follow `key`'s transcript on `res` (an open server-sent events stream):
--- the tail now, then each new event, then the run's state when it changes.
---@param key string
---@param res table
function M.watch(key, res)
  local snap = M.snapshot(key)
  res.event('snapshot', frame(snap))
  watchers[#watchers + 1] = {
    key = key,
    res = res,
    file = snap.file,
    offset = snap.offset,
    size = snap.size,
    running = snap.running,
    checked = uv.now(),
    sent = uv.now(),
  }
  M.start()
end

--- Stop following on `res`.
---@param res table
function M.unwatch(res)
  for i = #watchers, 1, -1 do
    if watchers[i].res == res then
      table.remove(watchers, i)
    end
  end
end

local function tick()
  local now = uv.now()
  local keep = {}
  for _, w in ipairs(watchers) do
    local alive = true
    -- a resumed session writes a newer file beside the old one
    if now - w.checked >= 1000 then
      w.checked = now
      local path = M.file(w.key)
      if path and path ~= w.file then
        local snap = M.snapshot(w.key)
        w.file, w.offset, w.size = snap.file, snap.offset, snap.size
        w.running = snap.running
        alive = w.res.event('reset', frame(snap))
      end
    end
    if alive and w.file then
      local blob, _, size = read_at(w.file, w.offset, CHUNK_BYTES)
      if blob and blob ~= '' then
        local lines, used = whole_lines(blob)
        local batch = events(lines)
        w.offset = w.offset + used
        w.size = size or w.size
        if #batch > 0 then
          alive = w.res.event('events', vim.json.encode { offset = w.offset, events = batch })
          w.sent = now
        end
      elseif blob == '' then
        w.size = size or w.size
      end
    end
    local running = M.pane(w.key) ~= nil
    if alive and running ~= w.running then
      w.running = running
      alive = w.res.event('status', vim.json.encode { running = running, offset = w.offset })
      w.sent = now
    end
    if alive and now - w.sent >= HEARTBEAT then
      w.sent = now
      alive = w.res.event('ping', '{}')
    end
    if alive then
      keep[#keep + 1] = w
    end
  end
  watchers = keep
  if #watchers == 0 then
    M.stop()
  end
end

--- Start the watchers' clock (a no-op while it runs).
function M.start()
  if timer then
    return
  end
  timer = uv.new_timer()
  timer:start(TICK, TICK, function()
    vim.schedule(tick)
  end)
end

--- Stop the clock.
function M.stop()
  if not timer then
    return
  end
  timer:stop()
  pcall(function()
    timer:close()
  end)
  timer = nil
end

return M
