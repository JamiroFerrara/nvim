-- The little window that says what the omp runs are doing, wherever you are.
--
-- Every run the launcher opens is a tmux pane, and the pane carries who it is
-- for: `@omp_ticket` (a ticket's :ID:) or `@omp_orchestrator` (a project's
-- session key, and the talking instance's -- `talk/one`, helpers/org/ai.lua).
-- It now carries what it was asked and when it started too
-- (`@omp_run_title`, `@omp_run_at`), which is all a window needs to draw the
-- run.
--
-- What it is doing now comes from the run's own transcript
-- (helpers/org/web/live.lua): the step the agent just said, the tool it picked
-- up, the question it is waiting on. The pane's screen is never read -- that
-- is a TUI, and the transcript already says it in one line.
--
-- The window is informational: it does not take the focus, so it can come up
-- while you are typing. `<leader>ov` (or `:OrgRuns`) toggles it, `q` closes it
-- from inside, and `<CR>` on a run brings that run's pane up in tmux.
--
-- `7` in the agenda is the same answer in the editor's own views
-- (`M.view`): it takes the window over the way the other numbered views do
-- and keeps itself up to date, so a list of runs is something you can read
-- and walk rather than a popup in the corner. `q` gives the window back.
--
-- It never opens on its own: it is down until you ask for it, and down again
-- once you close it. Nothing is polled while it is down, so a hidden window
-- costs nothing. It used to come up when the voice card started a run; that
-- is off for now, because a popup over the entry you are reading is noise.
-- The way back is one call -- `require('helpers.org.runs').show()` at the end
-- of the voice launcher (helpers/org/voice.lua, `launch`).

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

--- The window, its buffer, and the pane each of its lines jumps to.
local win, buf, line_panes, empty_since = nil, nil, {}, nil

--- The `7` view: the same answer as the little window, in the editor's own
--- view -- it takes the window over the way the agenda does, and `q` gives
--- the window back to the buffer it was showing.
local view_win, view_buf, view_prev, view_panes = nil, nil, nil, {}

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
    '#{pane_id}\t#{@omp_ticket}\t#{@omp_orchestrator}\t#{@omp_run_title}\t#{@omp_run_at}\t#{pane_dead}',
  }
  if vim.v.shell_error ~= 0 then
    return out
  end
  for line in vim.gsplit(raw or '', '\n', { plain = true }) do
    local pane, ticket, orchestrator, title, at, dead = line:match '^(%%%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(%d)$'
    if pane and dead == '0' then
      local key = ticket ~= '' and ticket or orchestrator
      if key and key ~= '' then
        out[pane] = {
          pane = pane,
          key = key,
          title = title ~= '' and title or key,
          at = tonumber(at) or nil,
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

--- One run as two lines: the head -- its state icon, what it was asked, how
--- long it has been going -- and below it the last thing it said. Both the
--- floating window and the `7` view draw a run this way.
---@param run table
---@param width integer
---@return string head
---@return string detail
---@return string icon
local function run_lines(run, width)
  local icon = run.alive and (run.line and run.line:match '^❓' and '❓' or '▶') or '✔'
  local when = run.alive and elapsed(os.time() - (run.started or os.time())) or 'done'
  local room = width - 4 - vim.fn.strdisplaywidth(icon) - 1 - vim.fn.strdisplaywidth(when)
  local head = icon .. ' ' .. pad(clip(run.title, math.max(1, room)), math.max(1, room)) .. when
  local detail = run.line
  if run.alive and not detail then
    detail = 'just started'
  end
  if not run.alive and not run.line then
    detail = 'finished'
  end
  return head, '  ' .. clip(detail or '', width - 4), icon
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
    local head, detail, icon = run_lines(run, width)
    lines[#lines + 1] = head
    marks[#lines] = { icon = icon, run = run }
    lines[#lines + 1] = detail
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
  -- `marks` is keyed by line number (one per run head, a detail line between
  -- two of them), so it is walked with pairs: ipairs stopped at the hole and
  -- only the first run ever got its icon, and the pane it jumps to.
  for lnum, mark in pairs(marks) do
    line_panes[lnum] = mark.run.pane
    local group = mark.icon == '❓' and 'DiagnosticWarn' or mark.icon == '✔' and 'DiagnosticOk' or 'DiagnosticInfo'
    vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, 0, { end_col = #mark.icon, hl_group = group })
  end
end

--- One look at the runs: who is there, and the step each live one is on.
---@return table[] entries
local function look()
  local entries = scan()
  for _, run in ipairs(entries) do
    if run.alive then
      run.line = activity(run.key) or run.line
    end
  end
  return entries
end

--- Is the `7` view on screen?
---@return boolean
local function view_open()
  return view_buf ~= nil
    and vim.api.nvim_buf_is_valid(view_buf)
    and view_win ~= nil
    and vim.api.nvim_win_is_valid(view_win)
    and vim.api.nvim_win_get_buf(view_win) == view_buf
end

--- Bring the `7` view's text in line with `entries`. The cursor stays where it
--- is unless it was left past the new end.
---@param entries table[]
local function view_draw(entries)
  if not view_open() then
    return
  end
  local width = math.max(20, vim.api.nvim_win_get_width(view_win) - 2)
  local alive = 0
  for _, run in ipairs(entries) do
    if run.alive then
      alive = alive + 1
    end
  end
  local count = ('%d running'):format(alive)
  if #entries > alive then
    count = count .. (' · %d just finished'):format(#entries - alive)
  end
  local title = ' omp runs'
  local header = pad(title, math.max(#title + 1, width - vim.fn.strdisplaywidth(count))) .. count
  local lines = { header }
  local hl = { { 1, 1, #title, 'Title' }, { 1, #title + 1, #header, 'Comment' } }
  local panes = {}
  if #entries == 0 then
    lines[#lines + 1] = ''
    lines[#lines + 1] = vim.fn.executable 'tmux' == 1 and ' no omp instance is running' or ' tmux is not running here'
    hl[#hl + 1] = { #lines, 1, #lines[#lines], 'Comment' }
  end
  local section = nil
  for _, run in ipairs(entries) do
    local want = run.alive and 'Running' or 'Just finished'
    if want ~= section then
      section = want
      lines[#lines + 1] = ''
      lines[#lines + 1] = ' ' .. section
      hl[#hl + 1] = { #lines, 1, #lines[#lines], 'Title' }
      lines[#lines + 1] = ''
    end
    local head, detail, icon = run_lines(run, width)
    lines[#lines + 1] = ' ' .. head
    panes[#lines] = run.pane
    local group = icon == '❓' and 'DiagnosticWarn' or icon == '✔' and 'DiagnosticOk' or 'DiagnosticInfo'
    hl[#hl + 1] = { #lines, 2, 2 + #icon, group }
    lines[#lines + 1] = detail
    hl[#hl + 1] = { #lines, 1, #lines[#lines], 'Comment' }
  end

  local lnum = math.min(vim.api.nvim_win_get_cursor(view_win)[1], #lines)
  vim.bo[view_buf].modifiable = true
  vim.api.nvim_buf_set_lines(view_buf, 0, -1, false, lines)
  vim.bo[view_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(view_buf, ns, 0, -1)
  for _, mark in ipairs(hl) do
    vim.api.nvim_buf_set_extmark(view_buf, ns, mark[1] - 1, mark[2] - 1, {
      end_col = mark[3] - 1,
      hl_group = mark[4],
    })
  end
  vim.api.nvim_win_set_cursor(view_win, { lnum, 0 })
  view_panes = panes
end

--- The pane the `7` view's line names, if it names one.
---@return string|nil
local function view_pane()
  local lnum = vim.api.nvim_win_get_cursor(view_win)[1]
  return view_panes[lnum]
end

local function view_jump()
  local pane = view_pane()
  if not pane then
    return
  end
  M.hide_view()
  vim.fn.system { 'tmux', 'select-window', '-t', pane }
  vim.fn.system { 'tmux', 'select-pane', '-t', pane }
end

--- Close the `7` view and give the window back to the buffer it was showing.
function M.hide_view()
  local win_, buf_, prev = view_win, view_buf, view_prev
  view_win, view_buf, view_prev, view_panes = nil, nil, nil, {}
  if win_ and vim.api.nvim_win_is_valid(win_) and buf_ and vim.api.nvim_buf_is_valid(buf_) and vim.api.nvim_win_get_buf(win_) == buf_ then
    if prev and vim.api.nvim_buf_is_valid(prev) and vim.fn.bufloaded(prev) == 1 then
      vim.api.nvim_win_set_buf(win_, prev)
    else
      vim.api.nvim_win_set_buf(win_, vim.api.nvim_create_buf(true, false))
    end
  end
  if buf_ and vim.api.nvim_buf_is_valid(buf_) then
    pcall(vim.api.nvim_buf_delete, buf_, { force = true })
  end
end

--- The `7` view: every run on one screen, in the window you are in -- the
--- editor's own answer to the question the little window answers, for when a
--- popup in the corner is not a place you can read a list. It takes the window
--- over (the agenda's `window = 'current'`), so the digits still switch views,
--- and it keeps itself up to date while it is on screen.
function M.view()
  if view_open() then
    if vim.api.nvim_get_current_win() == view_win then
      M.hide_view()
      return
    end
    vim.api.nvim_set_current_win(view_win)
    return
  end
  local prev = vim.api.nvim_get_current_buf()
  local created = vim.api.nvim_create_buf(false, true)
  pcall(vim.api.nvim_buf_set_name, created, 'omp runs')
  vim.bo[created].buftype = 'nofile'
  vim.bo[created].bufhidden = 'wipe'
  vim.bo[created].swapfile = false
  vim.bo[created].undolevels = -1
  vim.bo[created].modifiable = false
  view_win, view_buf, view_prev, view_panes = vim.api.nvim_get_current_win(), created, prev, {}
  vim.api.nvim_win_set_buf(view_win, created)
  vim.wo[view_win].number = false
  vim.wo[view_win].relativenumber = false
  vim.wo[view_win].signcolumn = 'no'
  vim.wo[view_win].wrap = false
  vim.wo[view_win].cursorline = true
  vim.wo[view_win].foldenable = false
  vim.wo[view_win].spell = false
  vim.wo[view_win].list = false
  vim.wo[view_win].colorcolumn = ''
  vim.keymap.set('n', 'q', M.hide_view, { buffer = created, desc = 'runs: close the view' })
  vim.keymap.set('n', '<Esc>', M.hide_view, { buffer = created, desc = 'runs: close the view' })
  vim.keymap.set('n', 'g', function()
    view_draw(look())
  end, { buffer = created, desc = 'runs: look again' })
  vim.keymap.set('n', '<CR>', view_jump, { buffer = created, desc = 'runs: jump to the run' })
  vim.bo[created].filetype = 'orgagenda'
  view_draw(look())
end

--- One look at the runs, and whatever is on screen brought in line with them.
--- Only a surface already open is drawn: a tick never opens one, and a surface
--- that is down is not looked at at all -- no tmux call, no transcript read.
function M.sync()
  local shown = view_open()
  local popup = win and vim.api.nvim_win_is_valid(win)
  if not (shown or popup) then
    return
  end
  local entries = look()
  if shown then
    view_draw(entries)
  end
  if popup then
    render(entries)
    if #entries == 0 then
      empty_since = empty_since or os.time()
      if os.time() - empty_since >= IDLE_HIDE then
        close()
      end
    else
      empty_since = nil
    end
  end
end

--- Open the window (`<leader>ov`, `:OrgRuns`). It is a look you asked for, so
--- it comes up even with no run in flight, and says so.
function M.show()
  empty_since = nil
  render(look())
end

--- Close the window; it stays down until it is asked for again.
function M.hide()
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
