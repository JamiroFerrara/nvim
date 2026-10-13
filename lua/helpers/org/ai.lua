-- OMP on an org ticket: `<leader>ai` in the TODO view (or an org buffer)
-- opens an `omp` instance for the headline at point, seeded with the ticket's
-- :ID: and file.
--
-- Layout: the first launch splits the nvim pane once with a vertical divider
-- (`split-window -h`, omp on the right). Once anything already sits beside
-- nvim, every later launch opens its own tmux window inserted after the
-- current one (`new-window -a`, the `prefix+n` equivalent) instead of stacking
-- panes in the right column, so each instance gets a full window. Each pane
-- carries the ticket's :ID: in its `@omp_ticket` pane option (the "already
-- running?" lookup) plus its window name / title. Splits and windows are
-- created detached (`-d`): the launch never moves the active pane or window
-- off nvim, so the cursor stays put.
--
-- The pane runs `nvim "+terminal omp …"`, the same shape as the tmux
-- default-command (`nvim +terminal`) every other pane uses, so the instance
-- lives in an nvim terminal buffer and navigates like the rest of the session
-- (Terminal-Normal vim keys, tmux `is_vim` pane moves).
--
-- The launcher owns the start of the run: it puts an :ID: on the headline
-- (reusing one already there), sets the state to NEXT, saves the file, and
-- only then starts omp. `<leader>aj` is the other direction: it jumps to the
-- pane of the ticket's already-running instance (the tmux `<prefix> i`
-- panel's jump); when nothing runs it, it resumes the ticket's session
-- interactively in a new window and lands there. Neither touches the
-- headline. Everything after that is the omp-org-ticket skill
-- appended to omp's system prompt: answer the `AI:` lines, resolve the
-- ticket, leave TEST/WARN/PEND (the user promotes TEST to DONE once they have
-- validated the change), write the <=2 line 🤖-headed summary, and remove a
-- temporary :ID:.
--
-- Each ticket is also linked to its omp session: the launcher writes an
-- `:OMP_SESSION:` key on the headline (the :ID: at the first launch, kept
-- across the temporary :ID: removal) and runs omp with `--session-dir` under
-- the agent directory, so a later launch `--continue`s that ticket's original
-- session — full context — instead of starting a fresh one.
--
-- The run is one-shot (`omp --print`): omp processes the ticket and exits; the
-- nvim terminal closes, its TermClose autocmd quits nvim, and tmux closes the
-- pane with it instead of parking an idle interactive session.
--
-- The agent edits the org file on disk, so nvim has to follow: a directory
-- watcher over the org tree (helpers/org/watch.lua) reloads changed,
-- unmodified org buffers and re-renders the agenda view with the cursor on
-- the same entry as soon as the file changes, and the FocusGained autocmd
-- below does the same for a change that happens while nvim was unfocused
-- (tmux `focus-events on` reports the pane switch).
local M = {}

local SKILL = vim.fn.expand '~/.agents/skills/omp-org-ticket/SKILL.md'

local function notify(msg, level)
  require('org.utils').notify(msg, level)
end

--- Run a tmux subcommand without a shell. Returns trimmed stdout, or nil plus
--- the shell error/output when tmux failed.
---@param args string[]
---@return string|nil, string|nil
local function tmux(args)
  local cmd = { 'tmux' }
  vim.list_extend(cmd, args)
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, vim.trim(out)
  end
  return vim.trim(out), nil
end

---@return boolean
local function in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ''
end

--- omp's agent directory: `PI_CODING_AGENT_DIR` when set, else omp's default
--- (`~/.omp/agent`). Ticket sessions live under it.
---@return string
local function agent_dir()
  local dir = vim.env.PI_CODING_AGENT_DIR
  if dir and dir ~= '' then
    return vim.fs.normalize(dir)
  end
  return vim.fn.expand '~/.omp/agent'
end

--- The headline property linking a ticket to its omp session directory. Its
--- value is the key fixed at the first launch (the :ID: then) and kept across
--- the temporary :ID: removal, so every later launch resumes that session.
local SESSION_PROP = 'OMP_SESSION'

--- The directory holding the ticket's omp session, or nil when the ticket
--- carries no key to key one on. The key is the :OMP_SESSION: link when there
--- is one; a ticket that never launched falls back to its :ID:, which is the
--- link the launch would have written — so a resume here and a later launch
--- land in the same directory.
---@param ticket OrgTicket
---@return string|nil
local function session_dir(ticket)
  local key = ticket.session and ticket.session:match '%S' and ticket.session
  if not key then
    key = ticket.id and ticket.id:match '%S' and ticket.id
  end
  if not key then
    return nil
  end
  return agent_dir() .. '/tickets/' .. key
end

--- Whether `dir` already holds a session file (so a launch there resumes).
---@param dir string
---@return boolean
local function has_session(dir)
  return #vim.fn.glob(dir .. '/*.jsonl', false, true) > 0
end

---@class OrgTicket
---@field bufnr integer
---@field lnum integer line of the headline
---@field id string
---@field temporary boolean the launcher created the :ID: (so it may remove it)
---@field session string|nil the :OMP_SESSION: link key (nil before the first launch)
---@field file string absolute org file path
---@field title string

--- The headline at the cursor, in an orgagenda or an org buffer. With
--- `mutate` set (the launch) a missing :ID: is created, the state is forced
--- to NEXT and the buffer saved; without it (the jump) nothing is written --
--- the headline is only read.
---@param mutate boolean
---@return OrgTicket|nil
local function ticket_at_cursor(mutate)
  local view = require 'org.agenda.view'
  local bufnr, lnum
  if vim.bo.filetype == 'orgagenda' then
    local item = view.item_at_cursor()
    if not item then
      notify('org ai: no agenda entry on this line', vim.log.levels.WARN)
      return nil
    end
    local target = view.resolve_target(item)
    if not target then
      return nil
    end
    bufnr, lnum = target.bufnr, target.lnum
  elseif vim.bo.filetype == 'org' then
    bufnr = vim.api.nvim_get_current_buf()
    lnum = vim.api.nvim_win_get_cursor(0)[1]
  else
    notify('org ai: not an org or agenda buffer', vim.log.levels.WARN)
    return nil
  end

  local file = require('org.files').get_buffer(bufnr)
  local hl = file:headline_on(lnum)
  if not hl then
    notify('org ai: not under a headline', vim.log.levels.WARN)
    return nil
  end

  local id = require('org.id').get { bufnr = bufnr, lnum = hl.line }
  local temporary = not (id and id:match '%S')
  local session = hl:get_property(SESSION_PROP, false)
  if mutate then
    if temporary then
      id = require('org.id').get_create { bufnr = bufnr, lnum = hl.line }
    end

    -- Link the ticket to its omp session: the key is the :ID: at the first
    -- launch, written to the drawer so it outlives the temporary :ID: and a
    -- later launch resumes the same session instead of starting fresh.
    if not (session and session:match '%S') then
      session = id
      require('org.properties').entry_put(bufnr, hl.line, SESSION_PROP, session)
    end

    -- NEXT is the launcher's, not the agent's; `force` skips blockers so the
    -- state is deterministic whatever the ticket carries.
    require('org.todo').change_state({ bufnr = bufnr, lnum = hl.line }, 'NEXT', { force = true })
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if mutate then
    local saved = pcall(vim.api.nvim_buf_call, bufnr, function()
      vim.cmd 'silent! write'
    end)
    if not saved then
      notify('org ai: could not save ' .. vim.fn.fnamemodify(path, ':t'), vim.log.levels.WARN)
    end
  end

  return {
    bufnr = bufnr,
    lnum = hl.line,
    id = id,
    temporary = temporary,
    session = session,
    file = vim.fs.normalize(path),
    title = hl:plain_title(),
  }
end

--- The message omp starts with: the ticket's identity, the state the
--- launcher already applied, and whether the :ID: is the launcher's to
--- remove. One line, so it survives shell quoting in the pane.
---@param ticket OrgTicket
---@return string
local function prompt(ticket)
  return table.concat({
    'Org ticket launched by nvim <leader>ai.',
    'File: ' .. ticket.file .. '.',
    'ID: ' .. ticket.id .. ' (' .. (ticket.temporary and 'created by this launch; remove it when you finish' or 'pre-existing; leave it') .. ').',
    'Title: ' .. ticket.title .. '.',
    'State: the launcher already set it to NEXT.',
    'Follow the omp-org-ticket rules appended to your system prompt.',
  }, ' ')
end

--- The omp argv: the rules file then the ticket message. The skill file is
--- passed as a path (`--append-system-prompt` reads a single-line value as a
--- file when it exists), so the rules always reach omp, not only when the
--- model happens to pick the skill itself.
---
--- The session is linked to the ticket through `--session-dir`: every launch
--- on the same ticket writes into (and looks up) the same per-ticket directory,
--- so `--continue` there resumes the ticket's original session — full context,
--- instead of a fresh one. A ticket with no session file yet launches fresh
--- (no `--continue`), seeding the directory.
---
--- `--print` is what ends the run: an interactive `omp "<prompt>"` processes
--- the ticket and then sits at its own prompt forever, so the pane would never
--- exit. Non-interactive mode processes the ticket and exits; the nvim
--- terminal closes, its TermClose autocmd quits nvim, and tmux closes a pane
--- when its command exits, so the window goes away on its own.
---@param ticket OrgTicket
---@return string[]
local function omp_argv(ticket)
  local dir = session_dir(ticket)
  if not dir then
    return { 'omp', '--append-system-prompt', SKILL, prompt(ticket) }
  end
  local argv = { 'omp', '--session-dir', dir }
  if has_session(dir) then
    argv[#argv + 1] = '--continue'
  end
  argv[#argv + 1] = '--append-system-prompt'
  argv[#argv + 1] = SKILL
  argv[#argv + 1] = prompt(ticket)
  return argv
end

--- The omp argv run inside a terminal-only nvim: `nvim "+terminal omp …"`.
--- The pane then mirrors the tmux default-command (`nvim +terminal`) every
--- other pane uses — an nvim terminal buffer, so Terminal-Normal mode and the
--- tmux `is_vim` navigation work here too. `omp --print` still ends the run:
--- the terminal closes, the pane's TermClose autocmd quits nvim, and tmux
--- closes the pane with it. The whole `+terminal …` is one shell word (nvim
--- takes everything after `+` as the Ex command), and tmux runs the pane
--- through the shell, so each layer is quoted for the shell that reads it.
---@param argv string[]
---@return string
local function pane_command(argv)
  local omp = table.concat(vim.tbl_map(vim.fn.shellescape, argv), ' ')
  return table.concat(vim.tbl_map(vim.fn.shellescape, { 'nvim', '+terminal ' .. omp }), ' ')
end

--- The omp argv for an interactive instance on `ticket` — the shape the
--- `<prefix> i` panel lists and jumps to. A ticket with a session resumes it
--- (`--session-dir` + `--continue`, full context); one without starts fresh
--- with the ticket prompt. No `--print`: the session stays open at its own
--- prompt instead of exiting.
---@param ticket OrgTicket
---@return string[]
local function resume_argv(ticket)
  local dir = session_dir(ticket)
  if dir and has_session(dir) then
    return { 'omp', '--session-dir', dir, '--continue' }
  end
  local argv = { 'omp' }
  if dir then
    argv[#argv + 1] = '--session-dir'
    argv[#argv + 1] = dir
  end
  argv[#argv + 1] = '--append-system-prompt'
  argv[#argv + 1] = SKILL
  argv[#argv + 1] = prompt(ticket)
  return argv
end

--- Panes of the window holding `pane`, as { id, left, top, right, bottom, ticket }.
---@param pane string
---@return table[]
local function panes_of(pane)
  local out, err = tmux { 'list-panes', '-t', pane, '-F', '#{pane_id}\t#{pane_left}\t#{pane_top}\t#{pane_right}\t#{pane_bottom}\t#{@omp_ticket}' }
  if not out then
    if err and err ~= '' then
      notify('org ai: tmux: ' .. err, vim.log.levels.ERROR)
    end
    return {}
  end
  local panes = {}
  for line in vim.gsplit(out, '\n', { plain = true }) do
    -- the trailing `@omp_ticket` is empty on a pane that never ran a ticket,
    -- and `tmux()` trims it away with the trailing tab on the last line
    local id, l, t, r, b, ticket = line:match '^(.-)\t(%-?%d+)\t(%-?%d+)\t(%-?%d+)\t(%-?%d+)\t?(.*)$'
    if id then
      panes[#panes + 1] = { id = id, left = tonumber(l), top = tonumber(t), right = tonumber(r), bottom = tonumber(b), ticket = ticket }
    end
  end
  return panes
end

--- The pane already running `id`, anywhere on the server.
---@param id string
---@return string|nil pane id
local function running_pane(id)
  local out = tmux { 'list-panes', '-a', '-F', '#{pane_id}\t#{@omp_ticket}' }
  if not out then
    return nil
  end
  for line in vim.gsplit(out, '\n', { plain = true }) do
    local pane, ticket = line:match '^(.-)\t(.*)$'
    if pane and ticket == id then
      return pane
    end
  end
end

--- Put the attached client on `pane`: switch to its session, then select its
--- window and pane — the jump the `<prefix> i` panel performs, which works
--- across sessions where a bare `select-window` would not.
---@param pane string
local function focus_pane(pane)
  local loc = tmux { 'display-message', '-p', '-t', pane, '#{session_name}:#{window_index}.#{pane_index}' }
  local session, window, index = (loc or ''):match '^([^:]+):(%d+)%.(%d+)$'
  if not session then
    notify('org ai: could not resolve pane ' .. pane, vim.log.levels.ERROR)
    return
  end
  tmux { 'switch-client', '-t', session }
  tmux { 'select-window', '-t', session .. ':' .. window }
  tmux { 'select-pane', '-t', session .. ':' .. window .. '.' .. index }
end

--- The pane in `panes` holding `cur`, or nil.
---@param cur string
---@param panes table[]
---@return table|nil
local function pane_of(cur, panes)
  for _, p in ipairs(panes) do
    if p.id == cur then
      return p
    end
  end
end

--- Whether anything already sits to the right of `current` (its window is
--- already split). With the right column taken, the next run opens its own
--- window instead of extending that column.
---@param current table
---@param panes table[]
---@return boolean
local function right_column_taken(current, panes)
  for _, p in ipairs(panes) do
    if p.left >= current.right then
      return true
    end
  end
  return false
end

--- A detached split to the right of the nvim pane — the first run. `-d` makes
--- the pane without becoming the active one, so launching never pulls the
--- cursor out of nvim's pane.
---@param cur string the nvim pane
---@return string|nil new pane id
local function split_for_run(cur)
  local id = tmux { 'split-window', '-d', '-h', '-t', cur, '-P', '-F', '#{pane_id}' }
  return id or nil
end

--- A detached tmux window inserted after the current one (`new-window -a`, the
--- `prefix+n` equivalent), its pane born running the ticket's omp instance —
--- `new-window` with a command runs it directly, so no respawn is needed. `-d`
--- leaves the current window selected, so nvim keeps focus.
---@param ticket OrgTicket
---@return string|nil new pane id
local function window_for_run(ticket)
  local id = tmux {
    'new-window',
    '-d',
    '-a',
    '-n',
    '🤖 ' .. ticket.title,
    '-c',
    '#{pane_current_path}',
    '-P',
    '-F',
    '#{pane_id}',
    pane_command(omp_argv(ticket)),
  }
  return id or nil
end

--- Start `ticket` for the headline and hand it to omp. Nothing here moves the
--- active pane or window: a ticket already running is reported instead of
--- focused, and a new split or window is created detached (and, for the split,
--- respawned) without taking over. The trailing `select-pane` back to nvim's
--- pane is belt and braces, so focus is nvim's whatever tmux version is behind
--- this.
---@param ticket OrgTicket
local function open_pane(ticket)
  local running = running_pane(ticket.id)
  if running then
    notify('org ai: ' .. ticket.title .. ' is already running in pane ' .. running)
    return
  end

  local cur = vim.env.TMUX_PANE
  if not cur then
    notify('org ai: $TMUX_PANE is unset', vim.log.levels.ERROR)
    return
  end

  local panes = panes_of(cur)
  local me = pane_of(cur, panes)
  if not me then
    notify('org ai: could not resolve the current tmux pane', vim.log.levels.ERROR)
    return
  end

  local pane
  if right_column_taken(me, panes) then
    pane = window_for_run(ticket)
    if not pane then
      notify('org ai: could not open a tmux window', vim.log.levels.ERROR)
      return
    end
    tmux { 'set-option', '-p', '-t', pane, '@omp_ticket', ticket.id }
  else
    pane = split_for_run(cur)
    if not pane then
      notify('org ai: could not split the tmux window', vim.log.levels.ERROR)
      return
    end
    tmux { 'set-option', '-p', '-t', pane, '@omp_ticket', ticket.id }
    tmux { 'select-pane', '-t', pane, '-T', '🤖 ' .. ticket.title }
    local _, err = tmux { 'respawn-pane', '-k', '-t', pane, pane_command(omp_argv(ticket)) }
    if err then
      notify('org ai: ' .. err, vim.log.levels.ERROR)
    end
  end
  tmux { 'select-pane', '-t', cur }
end

--- Resume `ticket` with no pane of its own: open a tmux window running the
--- ticket's interactive omp session — inserted after the current one and
--- selected, so focus lands in it (what the jump is for). The pane carries the
--- ticket's :ID: in `@omp_ticket`, so the next `<leader>aj` finds and focuses
--- it instead of resuming again.
---@param ticket OrgTicket
local function resume_pane(ticket)
  local pane = tmux {
    'new-window',
    '-a',
    '-n',
    '🤖 ' .. ticket.title,
    '-c',
    '#{pane_current_path}',
    '-P',
    '-F',
    '#{pane_id}',
    pane_command(resume_argv(ticket)),
  }
  if not pane then
    notify('org ai: could not open a tmux window', vim.log.levels.ERROR)
    return
  end
  if ticket.id and ticket.id:match '%S' then
    tmux { 'set-option', '-p', '-t', pane, '@omp_ticket', ticket.id }
  end
end

--- Without tmux, the ticket still resolves: a plain nvim terminal in a right
--- split, closed again once the omp process exits (same end state as the
--- tmux pane). No pane is tracked, so a second launch on the same ticket
--- starts a second instance — the tmux path is the predictable one.
---@param ticket OrgTicket
local function open_window(ticket)
  vim.cmd 'belowright vert new'
  local win = vim.api.nvim_get_current_win()
  vim.fn.termopen(omp_argv(ticket), {
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
      end)
    end,
  })
end

--- Reload org files changed on disk under the loaded buffers and re-render
--- the agenda view. The agent writes to the file while nvim holds the
--- buffer, so a reload is what makes the write-back visible.
function M.sync()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and name:match '%.org$' then
      pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd 'silent! checktime'
      end)
    end
  end
  -- A rebuild, not just a redraw: `redo` re-reads the files and puts the
  -- cursor back on the entry it was on, so a write-back that shifts the
  -- lines does not move the cursor off the ticket being read. Skipped when
  -- no view was ever opened, so a background write does not pull the whole
  -- agenda machinery in.
  if package.loaded['org.agenda.view'] then
    pcall(function()
      require('org.agenda.view').redo()
    end)
  end
end

--- `<leader>ai` in an org or orgagenda buffer.
function M.launch()
  local ticket = ticket_at_cursor(true)
  if not ticket then
    return
  end
  if in_tmux() then
    open_pane(ticket)
  else
    open_window(ticket)
  end
  M.sync()
end

--- `<leader>aj` in an org or orgagenda buffer: jump to the tmux pane running
--- the ticket at point, like tmux's `<prefix> i` panel jump. When nothing runs
--- it, the ticket's omp session is resumed instead — an interactive instance
--- (`--continue` where a session exists) opened in its own tmux window and
--- focused. The headline itself is never written to.
function M.jump()
  if not in_tmux() then
    notify('org ai: not in tmux', vim.log.levels.WARN)
    return
  end
  local ticket = ticket_at_cursor(false)
  if not ticket then
    return
  end
  if ticket.id and ticket.id:match '%S' then
    local pane = running_pane(ticket.id)
    if pane then
      focus_pane(pane)
      return
    end
  end
  if not session_dir(ticket) then
    notify('org ai: no omp session for ' .. ticket.title, vim.log.levels.WARN)
    return
  end
  resume_pane(ticket)
end

function M.setup()
  vim.api.nvim_create_autocmd('FocusGained', {
    callback = function()
      M.sync()
    end,
    desc = 'org ai: pick up an agent write-back on focus',
  })
  -- A detached omp pane writes the ticket file without ever taking the
  -- focus off nvim, so FocusGained never fires for it. The tree watcher
  -- (helpers/org/watch.lua) is what makes the view follow the file live.
  local ok, cfg = pcall(require, 'org.config')
  local root = (ok and cfg.opts and cfg.opts.org_directory) or '~/org'
  require('helpers.org.watch').start(root, M.sync)
end

return M
