-- OMP on an org ticket: `<leader>ai` in the TODO view (or an org buffer)
-- opens an `omp` instance for the headline at point, in a tmux pane beside
-- nvim, seeded with the ticket's :ID: and file.
--
-- Layout: the first launch splits the nvim pane once with a vertical divider
-- (`split-window -h`, omp on the right); every later launch splits the right
-- column with `split-window -v`, so the right panel stacks instances. Each
-- pane carries the ticket's :ID: in its `@omp_ticket` pane option (the
-- "already running?" lookup) and its title. The splits are detached: the
-- launch never moves the active pane off nvim, so the cursor stays put.
--
-- The pane runs `nvim "+terminal omp …"`, the same shape as the tmux
-- default-command (`nvim +terminal`) every other pane uses, so the instance
-- lives in an nvim terminal buffer and navigates like the rest of the session
-- (Terminal-Normal vim keys, tmux `is_vim` pane moves).
--
-- The launcher owns the start of the run: it puts an :ID: on the headline
-- (reusing one already there), sets the state to NEXT, saves the file, and
-- only then starts omp. Everything after that is the omp-org-ticket skill
-- appended to omp's system prompt: answer the `AI:` lines, resolve the
-- ticket, leave DONE/WARN/PEND, write the <=2 line robot-icon summary, and
-- remove a temporary :ID:.
--
-- The run is one-shot (`omp --print`): omp processes the ticket and exits; the
-- nvim terminal closes, its TermClose autocmd quits nvim, and tmux closes the
-- pane with it instead of parking an idle interactive session.
--
-- The agent edits the org file on disk, so nvim has to follow: on FocusGained
-- (tmux `focus-events on` reports the pane switch) every changed, unmodified
-- org buffer is reloaded and the agenda view re-rendered.
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

---@class OrgTicket
---@field bufnr integer
---@field lnum integer line of the headline
---@field id string
---@field temporary boolean the launcher created the :ID: (so it may remove it)
---@field file string absolute org file path
---@field title string

--- The headline at the cursor, in an orgagenda or an org buffer.
---@return OrgTicket|nil
local function ticket_at_cursor()
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
  if temporary then
    id = require('org.id').get_create { bufnr = bufnr, lnum = hl.line }
  end

  -- NEXT is the launcher's, not the agent's; `force` skips blockers so the
  -- state is deterministic whatever the ticket carries.
  require('org.todo').change_state({ bufnr = bufnr, lnum = hl.line }, 'NEXT', { force = true })

  local path = vim.api.nvim_buf_get_name(bufnr)
  local saved = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd 'silent! write'
  end)
  if not saved then
    notify('org ai: could not save ' .. vim.fn.fnamemodify(path, ':t'), vim.log.levels.WARN)
  end

  return {
    bufnr = bufnr,
    lnum = hl.line,
    id = id,
    temporary = temporary,
    file = vim.fs.normalize(path),
    title = hl:plain_title(),
    body = body,
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
--- `--print` is what ends the run: an interactive `omp "<prompt>"` processes
--- the ticket and then sits at its own prompt forever, so the pane would never
--- exit. Non-interactive mode processes the ticket and exits; the nvim
--- terminal closes, its TermClose autocmd quits nvim, and tmux closes a pane
--- when its command exits, so the window goes away on its own.
---@param ticket OrgTicket
---@return string[]
local function omp_argv(ticket)
  return { 'omp', '--append-system-prompt', SKILL, prompt(ticket) }
end

--- The omp argv run inside a terminal-only nvim: `nvim "+terminal omp …"`.
--- The pane then mirrors the tmux default-command (`nvim +terminal`) every
--- other pane uses — an nvim terminal buffer, so Terminal-Normal mode and the
--- tmux `is_vim` navigation work here too. `omp --print` still ends the run:
--- the terminal closes, the pane's TermClose autocmd quits nvim, and tmux
--- closes the pane with it. The whole `+terminal …` is one shell word (nvim
--- takes everything after `+` as the Ex command), and tmux runs the pane
--- through the shell, so each layer is quoted for the shell that reads it.
---@param ticket OrgTicket
---@return string
local function pane_command(ticket)
  local omp = table.concat(vim.tbl_map(vim.fn.shellescape, omp_argv(ticket)), ' ')
  return table.concat(vim.tbl_map(vim.fn.shellescape, { 'nvim', '+terminal ' .. omp }), ' ')
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

--- Split once to the right of the nvim pane, then stack further runs inside
--- that right column. The split is detached (`-d`), so the new pane is made
--- without becoming the active one: launching never pulls the cursor out of
--- nvim's pane.
---@param cur string the nvim pane
---@param panes table[]
---@return string|nil new pane id
local function split_for_run(cur, panes)
  local current
  for _, p in ipairs(panes) do
    if p.id == cur then
      current = p
      break
    end
  end
  if not current then
    return nil
  end
  local column, bottom
  for _, p in ipairs(panes) do
    if p.left >= current.right and (not bottom or p.bottom > bottom.bottom) then
      column, bottom = p.id, p
    end
  end
  local id
  if column then
    id = tmux { 'split-window', '-d', '-v', '-t', column, '-P', '-F', '#{pane_id}' }
  else
    id = tmux { 'split-window', '-d', '-h', '-t', cur, '-P', '-F', '#{pane_id}' }
  end
  return id or nil
end

--- Start `ticket` in a pane beside nvim and hand it to omp. Nothing here
--- moves the active pane: a ticket already running is reported instead of
--- focused, and the new pane is created detached, titled, and respawned
--- without taking over (`respawn-pane` on an inactive pane leaves it
--- inactive). The trailing `select-pane` back to nvim's pane is belt and
--- braces, so focus is nvim's whatever tmux version is behind this.
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
  local pane = split_for_run(cur, panes_of(cur))
  if not pane then
    notify('org ai: could not split the tmux window', vim.log.levels.ERROR)
    return
  end
  tmux { 'set-option', '-p', '-t', pane, '@omp_ticket', ticket.id }
  tmux { 'select-pane', '-t', pane, '-T', '🤖 ' .. ticket.title }
  local cmd = pane_command(ticket)
  local _, err = tmux { 'respawn-pane', '-k', '-t', pane, cmd }
  if err then
    notify('org ai: ' .. err, vim.log.levels.ERROR)
  end
  tmux { 'select-pane', '-t', cur }
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
  pcall(function()
    require('org.agenda.view').refresh()
  end)
end

--- `<leader>ai` in an org or orgagenda buffer.
function M.launch()
  local ticket = ticket_at_cursor()
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

function M.setup()
  vim.api.nvim_create_autocmd('FocusGained', {
    callback = function()
      M.sync()
    end,
    desc = 'org ai: pick up an agent write-back on focus',
  })
end

return M
