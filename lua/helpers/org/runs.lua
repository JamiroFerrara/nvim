-- The little window that says what the omp runs are doing, wherever you are.
--
-- Every run the launcher opens is a tmux pane, and the pane carries who it is
-- for: `@omp_ticket` (a ticket's :ID:), `@omp_orchestrator` (a project's
-- session key), or `@omp_voice` (words that came from the voice card). It now
-- carries what it was asked and when it started too (`@omp_run_title`,
-- `@omp_run_at`), which is all a window needs to draw the run.
--
-- What it is doing now comes from the run's own transcript
-- (helpers/org/web/live.lua): the step the agent just said, the tool it picked
-- up, the question it is waiting on. The pane's screen is never read -- that
-- is a TUI, and the transcript already says it in one line.
--
-- The window is informational: it does not take the focus, so it can come up
-- while you are typing. `<leader>ov` (or `:OrgRuns`) toggles it, `q` closes it
-- from inside, and `<CR>` on a run brings that run's pane up in tmux. It comes
-- up by itself when the voice card starts a run -- the words go somewhere, and
-- that somewhere is what you are watching -- and stays down once you close it.

local M = {}

local uv = vim.uv or vim.loop

local TICK = 1000 -- ms between two looks at tmux
local WIDTH = 68 -- columns of the window
local MAX_ROWS = 14 -- the window never grows past this
local LINGER = 20 -- seconds a finished run stays in the list
local IDLE_HIDE = 6 -- seconds an empty window stays open before it closes
local ACTIVITY = 100 -- characters of the run's last step on screen

local ns = vim.api.nvim_create_namespace 'org_runs'

--- The runs the window knows about, by pane id. A pane that is gone stays here
--- for `LINGER` seconds so the window can say how it ended.
---@type table<string, table>
local known = {}

--- Has the user closed the window since the last run started? A new voice run
--- opens it again whatever this says.
local dismissed = false

--- The window, its buffer, and the pane each of its lines jumps to.
local win, buf, line_panes, empty_since = nil, nil, {}, nil

local timer = nil

local function in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ''
end

--- Clip `text` to `n` display columns, one line, ending in an ellipsis when it
--- had to be cut.
---@param text string
---@param n integer
---@return string
local function clip(text, n)
  local flat = tostring(text or ''):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if vim.fn.strdisplaywidth(flat) <= n then
    return flat
  end
  local cut = flat
  while cut ~= '' and vim.fn.strdisplaywidth(cut .. '…') > n do
    cut = vim.fn.strcharpart(cut, 0, vim.fn.strchars(cut) - 1)
  end
  return cut .. '…'
end

--- Right-pad `text` to `n` display columns so the next column lines up.
---@param text string
---@param n integer
---@return string
local function pad(text, n)
  local gap = n - vim.fn.strdisplaywidth(text)
  return gap > 0 and (text .. string.rep(' ', gap)) or text
end

--- How long a run has been going, in the shortest form that still says it.
---@param secs integer
---@return string
local function elapsed(secs)
  secs = math.max(0, math.floor(secs))
  if secs < 60 then
    return ('%ds'):format(secs)
  end
  if secs < 3600 then
    return ('%dm %02ds'):format(math.floor(secs / 60), secs % 60)
  end
  return ('%dh %02dm'):format(math.floor(secs / 3600), math.floor((secs % 3600) / 60))
end

--- The runs tmux is holding right now: one entry per pane the launcher marked.
--- A pane with no mark is the user's own shell and is not a run.
---@return table<string, table> by pane id
local function panes()
  local out = {}
  if vim.fn.executable 'tmux' ~= 1 then
    return out
  end
  local raw = vim.fn.system {
    'tmux',
    'list-panes',
    '-a',
    '-F',
    '#{pane_id}\t#{@omp_ticket}\t#{@omp_orchestrator}\t#{@omp_voice}\t#{@omp_run_title}\t#{@omp_run_at}\t#{pane_dead}',
  }
  if vim.v.shell_error ~= 0 then
    return out
  end
  for line in vim.gsplit(raw or '', '\n', { plain = true }) do
    local pane, ticket, orchestrator, voice, title, at, dead = line:match '^(%%%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d)$'
    if pane and dead == '0' then
      local key = ticket ~= '' and ticket or (orchestrator ~= '' and orchestrator or voice)
      if key and key ~= '' then
        out[pane] = {
          pane = pane,
          key = key,
          title = title ~= '' and title or key,
          at = tonumber(at) or nil,
          voice = voice ~= '',
          ticket = ticket ~= '',
        }
      end
    end
  end
  return out
end

--- The run's own record of what it is doing, in one line.
---@param key string
---@return string|nil
local function activity(key)
  local ok, live = pcall(require, 'helpers.org.web.live')
  if not ok then
    return nil
  end
  local ok_act, line = pcall(live.activity, key)
  return ok_act and line or nil
end

--- The last thing the run said, for a run that has stopped: what it did, in
--- its own words.
---@param key string
---@return string|nil
local function outcome(key)
  local ok, live = pcall(require, 'helpers.org.web.live')
  if not ok then
    return nil
  end
  local ok_snap, snap = pcall(live.snapshot, key)
  if not ok_snap or type(snap) ~= 'table' then
    return nil
  end
  for i = #snap.events, 1, -1 do
    local event = snap.events[i]
    if event.k == 'say' and event.t and event.t:match '%S' then
      return clip(event.t, ACTIVITY)
    end
  end
  return nil
end

--- Take one look at tmux: who is running, who stopped since the last look.
local function scan()
  local now = os.time()
  local alive = panes()
  local entries = {}
  for pane, run in pairs(alive) do
    local was = known[pane]
    run.alive = true
    run.started = run.at or (was and was.started) or now
    run.line = nil
    known[pane] = run
    entries[#entries + 1] = run
  end
  for pane, run in pairs(known) do
    if not alive[pane] then
      if run.alive ~= false then
        -- it stopped between two looks: freeze what it said last, because
        -- its transcript will not follow it into the pane's death
        run.alive = false
        run.ended = now
        run.line = activity(run.key) or outcome(run.key)
      end
      if now - (run.ended or now) <= LINGER then
        entries[#entries + 1] = run
      else
        known[pane] = nil
      end
    end
  end
  table.sort(entries, function(a, b)
    if a.alive ~= b.alive then
      return a.alive
    end
    return a.started < b.started
  end)
  return entries
end

local function close()
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  win, buf, line_panes, empty_since = nil, nil, {}, nil
end

--- Draw `entries` in the window, opening it first when it is not there.
---@param entries table[]
local function render(entries)
  local width = math.max(10, math.min(WIDTH, vim.o.columns - 4))
  local lines, marks = {}, {}
  if #entries == 0 then
    lines[1] = 'no omp run in flight'
  end
  for _, run in ipairs(entries) do
    local icon = run.alive and (run.line and run.line:match '^❓' and '❓' or '▶') or '✔'
    local when = run.alive and elapsed(os.time() - (run.started or os.time())) or 'done'
    local room = width - 4 - vim.fn.strdisplaywidth(icon) - 1 - vim.fn.strdisplaywidth(when)
    local title = clip(run.title, math.max(1, room))
    local head = icon .. ' ' .. pad(title, math.max(1, room)) .. when
    lines[#lines + 1] = head
    marks[#lines] = { icon = icon, run = run }
    local detail = run.line
    if run.alive and not detail then
      detail = 'just started'
    end
    if not run.alive and not run.line then
      detail = 'finished'
    end
    lines[#lines + 1] = '  ' .. clip(detail or '', width - 4)
  end

  local height = math.min(MAX_ROWS, math.max(3, #lines))
  if not (win and vim.api.nvim_win_is_valid(win)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].swapfile = false
    vim.bo[buf].undolevels = -1
    win = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      anchor = 'SE',
      row = vim.o.lines - 3,
      col = vim.o.columns - 2,
      width = width,
      height = height,
      style = 'minimal',
      border = 'rounded',
      title = ' omp ',
      title_pos = 'center',
      footer = ' q hide · <CR> jump ',
      footer_pos = 'center',
      zindex = 40,
    })
    vim.wo[win].wrap = false
    vim.keymap.set('n', 'q', close, { buffer = buf, desc = 'runs: hide' })
    vim.keymap.set('n', '<Esc>', close, { buffer = buf, desc = 'runs: hide' })
    vim.keymap.set('n', '<CR>', function()
      local pane = line_panes[vim.api.nvim_win_get_cursor(0)[1]]
      if not pane then
        return
      end
      close()
      vim.fn.system { 'tmux', 'select-window', '-t', pane }
      vim.fn.system { 'tmux', 'select-pane', '-t', pane }
    end, { buffer = buf, desc = 'runs: jump to the run' })
  else
    pcall(vim.api.nvim_win_set_config, win, {
      relative = 'editor',
      anchor = 'SE',
      row = vim.o.lines - 3,
      col = vim.o.columns - 2,
      width = width,
      height = height,
    })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  line_panes = {}
  for i, mark in ipairs(marks) do
    line_panes[i] = mark.run.pane
    local group = mark.icon == '❓' and 'DiagnosticWarn' or mark.icon == '✔' and 'DiagnosticOk' or 'DiagnosticInfo'
    vim.api.nvim_buf_set_extmark(buf, ns, i - 1, 0, { end_col = #mark.icon, hl_group = group })
  end
end

--- One look at the runs, and the window brought in line with them.
function M.sync()
  if dismissed and not (win and vim.api.nvim_win_is_valid(win)) then
    -- closed by the user: nothing to draw until a new voice run asks for it
    return
  end
  local entries = scan()
  local running = false
  for _, run in ipairs(entries) do
    if run.alive then
      running = true
      run.line = activity(run.key) or run.line
    end
  end
  if win and vim.api.nvim_win_is_valid(win) then
    render(entries)
    if #entries == 0 then
      empty_since = empty_since or os.time()
      if os.time() - empty_since >= IDLE_HIDE then
        close()
      end
    else
      empty_since = nil
    end
    return
  end
  if not dismissed and running then
    empty_since = nil
    render(entries)
  end
end

--- Open the window (and keep it open against a run that ends right away).
function M.show()
  dismissed = false
  M.sync()
end

--- Close the window, and leave it closed for the runs already in flight.
function M.hide()
  dismissed = true
  close()
end

--- `<leader>ov` / `:OrgRuns`: open it when it is down, close it when it is up.
function M.toggle()
  if win and vim.api.nvim_win_is_valid(win) then
    M.hide()
  else
    M.show()
  end
end

function M.setup()
  vim.api.nvim_create_user_command('OrgRuns', function()
    M.toggle()
  end, { desc = 'org runs: what the omp instances are doing' })
  if not in_tmux() then
    return
  end
  if timer then
    return
  end
  timer = uv.new_timer()
  timer:start(TICK, TICK, function()
    vim.schedule(function()
      pcall(M.sync)
    end)
  end)
end

return M
