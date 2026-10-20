-- OMP on an org ticket: `<leader>ai` in the TODO view (or an org buffer)
-- opens an `omp` instance for the headline at point, seeded with the ticket's
-- :ID: and file. Over a Visual selection it is that same launch applied to
-- every entry the selection covers (M.launch_range), one instance each.
--
-- A launch lands on what is takeable under the headline, not on the headline
-- itself: the frontier -- the tickets open with nothing open below them
-- (expand_target's `frontier`) -- because a ticket nested under another is
-- blocked by it (skill://wayfinder/org-tracker.md: the vault has no
-- dependency relationship of its own, so "where a ticket sits is its
-- blocking, children first"). A headline with open work under it is
-- therefore a container, not a ticket of its own: the launch walks down
-- through it, past every open ticket still waiting on its own subtree, to
-- the leaves that block them, one instance each, and the containers
-- themselves are stamped with nothing. Launching the root of a charted chain
-- starts the task at its bottom, and once that task is done the ticket above
-- it holds nothing open below it in turn, so the next launch lands on that
-- one -- the frontier climbing the chain as its leaves close. A headline
-- with nothing open under it -- a leaf ticket above all, and the map of an
-- expedition whose tickets are all closed -- launches itself, exactly as
-- before.
--
-- In an open capture buffer the same key finishes the capture first -- the
-- entry is filed at its template's destination and the target file written --
-- and launches on the entry it just stored, so `<leader>ai` captures and
-- starts the run in one stroke instead of reading the capture buffer's
-- scratch text as a headline.
--
-- A note on an entry in TEST starts the same run without the key: the entry
-- is waiting on the user's validation, so a note there is their answer to it
-- and helpers/org/notes.lua hands the headline to M.launch_at once the note
-- is stored -- the agent reads the note as the ticket's new body. Every
-- other state just stores the note.
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
-- The pane runs `nvim "+terminal sh <script>"`, the same shape as the tmux
-- default-command (`nvim +terminal`) every other pane uses, so the instance
-- lives in an nvim terminal buffer and navigates like the rest of the session
-- (Terminal-Normal vim keys, tmux `is_vim` pane moves); the script holds the
-- omp invocation, which `:terminal` would otherwise mangle, `%` and `#` in a
-- ticket title first of all.
--
-- The launcher owns the start of the run: it puts an :ID: on the headline
-- (reusing one already there), sets the state to NEXT, saves the file, and
-- only then starts omp. Before that hand-off it also commits whatever the
-- ticket's project leaves pending (helpers/org/project.lua's
-- `#+PROJECT_DIRS:` claims, one commit per repo, never a push): that commit
-- is the revert point, so a run that goes wrong is undone with
-- `git reset --hard` back to it instead of unpicking a dirty tree.
-- `<leader>aj` is the other direction: it jumps to the
-- pane of the ticket's already-running instance (the tmux `<prefix> i`
-- panel's jump); when nothing runs it, it resumes the ticket's session
-- interactively in a new window and lands there. Neither touches the
-- headline. Everything after that is the omp-org-ticket skill
-- appended to omp's system prompt: answer the `AI:` lines, resolve the
-- ticket, leave TEST/WARN/PEND (the user promotes TEST to DONE once they have
-- validated the change), and write the <=2 line 🤖-headed summary -- its text
-- in an org `markdown` source block. The headline's :ID: stays: it is the
-- anchor the knowledge base links the ticket by, so neither side removes it.
--
-- Each ticket is also linked to its omp session: the launcher writes an
-- `:OMP_SESSION:` key on the headline (the :ID: at the first launch) and runs
-- omp with `--session-dir` under
-- the agent directory, so a later launch `--continue`s that ticket's original
-- session — full context — instead of starting a fresh one.
--
-- The run ends by killing its own pane. omp runs interactively, so the user
-- watches the ticket's TUI in the pane; an interactive omp then waits at its
-- own prompt forever, so the skill's last step is the agent killing the pane
-- it runs in: `tmux kill-pane` on its own `$TMUX_PANE`, issued through
-- `run-shell -b` so the tmux server -- not the dying pane -- runs it, and
-- guarded on the pane's `@omp_ticket`, so a pane the user opened by hand is
-- left alone. Should the agent die before that step, the pane still goes away
-- when its omp is quit: the nvim terminal closes, its TermClose autocmd quits
-- nvim, and tmux closes the pane with it.
--
-- The agent edits the org file on disk, so nvim has to follow: a directory
-- watcher over the org tree (helpers/org/watch.lua) reloads changed,
-- unmodified org buffers and re-renders the agenda view with the cursor on
-- the same entry as soon as the file changes, and the FocusGained autocmd
-- below does the same for a change that happens while nvim was unfocused
-- (tmux `focus-events on` reports the pane switch).
local M = {}

local SKILL = vim.fn.expand '~/.agents/skills/omp-org-ticket/SKILL.md'

-- every write of a ticket file goes through it: the file is written by the
-- agents of the tickets already running too (helpers/org/write.lua)
local write = require 'helpers.org.write'

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
--- value is the key fixed at the first launch (the :ID: then), so every later
--- launch resumes that session.
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
---@field id string the headline's permanent :ID: (the launch creates it when missing)
---@field session string|nil the :OMP_SESSION: link key (nil before the first launch)
---@field file string absolute org file path
---@field title string

--- The source entry of the entry preview: `<CR>` in the agenda (the
--- `entry_scratch` action, helpers/org/agenda.lua) shows a copy of one entry
--- in a scratch org buffer, which carries its source buffer and the extmark
--- on the entry's first line in `org_entry_source` / `org_entry_mark`. A
--- launch from the preview must act on that real headline -- the scratch's
--- `org-entry://` name is not a file omp could read -- so resolve the pair
--- here, the way write_back reads it. Returns nil when the current buffer is
--- not such a preview.
---@return integer|nil bufnr
---@return integer|nil lnum
local function preview_source()
  local src = vim.b.org_entry_source
  local mark = vim.b.org_entry_mark
  if not (src and mark and vim.api.nvim_buf_is_valid(src)) then
    return nil
  end
  local pos = vim.api.nvim_buf_get_extmark_by_id(src, vim.api.nvim_create_namespace 'org_entry_scratch', mark, {})
  if not pos[1] then
    return nil
  end
  return src, pos[1] + 1
end

--- The buffer of the open capture buffer at the cursor, or nil. org.nvim
--- registers a capture session per buffer (`org.capture.sessions`), for both
--- capture ways in (the `^` Task capture and the `c` / <leader>aC
--- capture-under-entry), and clears it once the capture ends, so the entry is
--- only ever an editor state while the capture is open.
---@return integer|nil
local function capture_buffer()
  local capture = package.loaded['org.capture']
  local buf = vim.api.nvim_get_current_buf()
  if capture and capture.sessions[buf] then
    return buf
  end
end

--- Store the capture open in `buf` and return the entry it landed on: the
--- template's own destination resolution is what places it (the working
--- directory's project, the picker otherwise), and the target file is written
--- by the store itself, so the launch that follows reads a real headline on
--- disk. Returns nil, with a notification, when nothing was stored -- the
--- capture stays open, with its text, exactly as a failing `<C-c><C-c>`
--- leaves it.
---@param buf integer
---@return integer|nil bufnr
---@return integer|nil lnum
local function finalize_capture(buf)
  local capture = package.loaded['org.capture']
  local ok, dbuf, dline = pcall(capture.finalize, buf, { jump = false })
  if not ok then
    notify('org ai: ' .. tostring(dbuf), vim.log.levels.WARN)
    return nil
  end
  if not (dbuf and dline) then
    notify('org ai: the capture was not stored', vim.log.levels.WARN)
    return nil
  end
  return dbuf, dline
end

--- The buffer line of the headline the cursor is on: the entry at point in
--- the agenda / TODO view, resolved to its source buffer; the headline at
--- the cursor in an org buffer -- or the real headline behind the
--- `org-entry` preview scratch. nil, with a notification, when the cursor is
--- nowhere near a headline.
---
--- An open capture buffer is not a ticket: its `* TODO` line looks like a
--- headline but no file holds it yet. With `store_capture` set (the launch)
--- the capture is finished first -- filed at its destination, the target file
--- written -- and the launch acts on the stored headline, so one key captures
--- and starts the run; the capture stays open, and the launch aborts, when it
--- could not be stored. Without it (the jump) nothing is written: the entry
--- to jump to does not exist before the capture is filed.
---@param store_capture? boolean
---@return integer|nil bufnr
---@return integer|nil lnum
local function target_at_cursor(store_capture)
  local capture_buf = capture_buffer()
  if capture_buf then
    if store_capture then
      return finalize_capture(capture_buf)
    end
    notify('org ai: the capture is not stored yet -- <leader>ai stores it and launches', vim.log.levels.WARN)
    return nil
  end
  local view = require 'org.agenda.view'
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
    return target.bufnr, target.lnum
  end
  if vim.bo.filetype == 'org' then
    local bufnr, lnum = preview_source()
    if bufnr then
      return bufnr, lnum
    end
    return vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)[1]
  end
  notify('org ai: not an org or agenda buffer', vim.log.levels.WARN)
end

--- The ticket for the headline at `lnum` of `bufnr`, in an orgagenda or an
--- org buffer. With `mutate` set (the launch) a missing :ID: is created, the
--- state is forced to NEXT and the buffer saved; without it (the jump)
--- nothing is written -- the headline is only read.
---@param bufnr integer
---@param lnum integer
---@param mutate boolean
---@return OrgTicket|nil
local function ticket_at(bufnr, lnum, mutate)
  local file = require('org.files').get_buffer(bufnr)
  local hl = file:headline_on(lnum)
  if not hl then
    notify('org ai: not under a headline', vim.log.levels.WARN)
    return nil
  end

  local id = require('org.id').get { bufnr = bufnr, lnum = hl.line }
  local missing_id = not (id and id:match '%S')
  local session = hl:get_property(SESSION_PROP, false)
  if mutate then
    if missing_id then
      id = require('org.id').get_create { bufnr = bufnr, lnum = hl.line }
    end

    -- Link the ticket to its omp session: the key is the :ID: at the first
    -- launch, written to the drawer, so a later launch resumes the same
    -- session instead of starting fresh.
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
    local saved = write.save(bufnr)
    if not saved then
      notify('org ai: could not save ' .. vim.fn.fnamemodify(path, ':t'), vim.log.levels.WARN)
    end
  end

  return {
    bufnr = bufnr,
    lnum = hl.line,
    id = id,
    session = session,
    file = vim.fs.normalize(path),
    title = hl:plain_title(),
  }
end

--- The headline at the cursor, in an orgagenda or an org buffer (ticket_at
--- on target_at_cursor). `mutate` is the launch, and it is also what lets an
--- open capture buffer be filed (target_at_cursor's `store_capture`): the
--- jump (`<leader>aj`) never stores a half-typed capture.
---@param mutate boolean
---@return OrgTicket|nil
local function ticket_at_cursor(mutate)
  local bufnr, lnum = target_at_cursor(mutate)
  if not bufnr then
    return nil
  end
  return ticket_at(bufnr, lnum, mutate)
end

--- The takeable tickets under `hl`, in file order: the wayfinder frontier --
--- open, with nothing open below them. A ticket's children are its blockers
--- (skill://wayfinder/org-tracker.md: blocking is the nesting, children
--- first), so a ticket is not takeable while its own subtree still holds
--- open work: the walk descends into every such subtree -- `hl`'s child when
--- that child has unfinished work, however deep the frontier sits -- and
--- collects the open headlines that hold none, the leaves blocking
--- everything above them. A headline that is no ticket (no keyword: a
--- grouping line) is walked through, never collected, and a subtree of done
--- tickets holds nothing to collect either. `hl` itself is no candidate: it
--- is what is being launched, and expand_target falls back to it when the
--- walk finds nothing.
---@param hl org.Headline
---@param out org.Headline[]
local function frontier(hl, out)
  for _, child in ipairs(hl.children) do
    if child:has_undone_children() then
      frontier(child, out)
    elseif child:is_todo() then
      out[#out + 1] = child
    end
  end
end

--- The headlines a launch on the entry at `lnum` of `bufnr` covers: the
--- frontier below it (see `frontier`), one instance each, or the entry
--- itself when it has nothing open under it. An entry with open work below
--- it is a container, not a ticket of its own: launching its root would
--- stamp the container, whose :ID: / NEXT / hand-back describe the whole
--- subtree, while the ticket the run could work -- the leaf blocking it --
--- stayed untouched. So a launch walks down to those leaves, which is what
--- makes launching a charted chain start the task at its bottom; once that
--- task is done the ticket above it has nothing open below it in turn, and
--- the next launch lands on that one -- the frontier climbing the chain as
--- its leaves close. A leaf ticket, and the map of an expedition whose
--- tickets are all closed, has no frontier below it and is launched itself.
--- The leaves are distinct headlines, so no two instances claim the same
--- one.
---@param bufnr integer
---@param lnum integer
---@return { bufnr: integer, lnum: integer }[]
local function expand_target(bufnr, lnum)
  local file = require('org.files').get_buffer(bufnr)
  local hl = file and file:headline_on(lnum)
  local leaves = {}
  if hl then
    frontier(hl, leaves)
  end
  if #leaves == 0 then
    return { { bufnr = bufnr, lnum = lnum } }
  end
  local targets = {}
  for _, leaf in ipairs(leaves) do
    targets[#targets + 1] = { bufnr = bufnr, lnum = leaf.line }
  end
  return targets
end

--- Run `git` in `root` — the rest of `args` its argv — without a shell.
---@param root string
---@param args string[]
---@return vim.SystemCompleted
local function git(root, args)
  local cmd = { 'git', '-C', root }
  vim.list_extend(cmd, args)
  return vim.system(cmd, { text = true }):wait()
end

--- git's own words for a failed run, one line, or its exit code when it
--- said nothing (a pre-commit hook that fails silently).
---@param res vim.SystemCompleted
---@return string
local function git_error(res)
  local msg = vim.trim((res.stderr or '') .. ' ' .. (res.stdout or '')):gsub('%s+', ' ')
  return msg ~= '' and msg or ('exit ' .. res.code)
end

--- One commit of everything pending in `root`, never a push. `true` when it
--- committed, `false` when the tree was already clean, nil plus the error
--- when git failed (bad repo, a rejected hook, nothing to commit).
---@param root string
---@param subject string
---@return boolean|nil committed, string|nil err
local function snapshot(root, subject)
  local status = git(root, { 'status', '--porcelain' })
  if status.code ~= 0 then
    return nil, git_error(status)
  end
  if not status.stdout:match '%S' then
    return false
  end
  git(root, { 'add', '-A' })
  local commit = git(root, { 'commit', '--quiet', '-m', subject })
  if commit.code ~= 0 then
    return nil, git_error(commit)
  end
  return true
end

--- The checkpoint's commit subject, in the shape every commit of a ticket run
--- follows (`<icon> <type>(<scope>): <summary>`, the omp-org-ticket skill):
--- the ticket's title on one line, cut at a word boundary when it would push
--- the subject past git's 72-character soft limit.
---@param title string
---@return string
local function checkpoint_subject(title)
  local prefix = '🧹 chore(omp): checkpoint before '
  local summary = vim.trim((title or ''):gsub('%s+', ' '))
  local room = 72 - vim.fn.strchars(prefix)
  if vim.fn.strchars(summary) > room then
    summary = vim.fn.strcharpart(summary, 0, room - 1):gsub('%s+%S*$', '') .. '…'
  end
  return prefix .. summary
end

--- Commit the pending work of every repo the ticket's project claims — the
--- repository as the user left it, before the agent touches it. This is the
--- revert point: a run that goes wrong is undone with `git reset --hard` to
--- it, so it costs little. Never a push, and never a commit on a clean tree.
--- The ticket's file names the repos through its `#+PROJECT_DIRS:` claims
--- (helpers/org/project.lua); a repo that will not commit is reported and
--- the launch goes on.
---@param ticket OrgTicket
local function checkpoint(ticket)
  local dirs = require('helpers.org.project').dirs(ticket.file, ticket.lnum)
  local seen, roots = {}, {}
  for _, dir in ipairs(dirs) do
    local root = vim.fs.root(dir, '.git')
    if root and not seen[root] then
      seen[root] = true
      roots[#roots + 1] = root
    end
  end

  local subject = checkpoint_subject(ticket.title)
  local done, failed = {}, {}
  for _, root in ipairs(roots) do
    local name = vim.fn.fnamemodify(root, ':t')
    local committed, err = snapshot(root, subject)
    if committed == nil then
      failed[#failed + 1] = name .. ' (' .. vim.trim(err or 'git failed') .. ')'
    elseif committed then
      done[#done + 1] = name
    end
  end
  if #done > 0 then
    notify('org ai: checkpointed ' .. table.concat(done, ', '))
  end
  if #failed > 0 then
    notify('org ai: no checkpoint in ' .. table.concat(failed, '; '), vim.log.levels.WARN)
  end
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
    'ID: ' .. ticket.id .. ' (permanent: the knowledge base links this ticket by it; never remove it).',
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
--- The run ends by killing its own pane, not through `--print`: non-interactive
--- mode draws no TUI -- the pane sat on a bare `Working…`, with no progress to
--- watch -- while an interactive `omp "<prompt>"` shows the ticket being worked
--- and then waits at its own prompt forever, so the pane would never exit on
--- its own. The skill's last step closes that gap: the agent kills the pane it
--- runs in (the module header has the mechanism), so the argv stays the
--- interactive one.
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

--- The omp argv run inside a terminal-only nvim: `nvim "+terminal sh <script>"`.
--- The pane then mirrors the tmux default-command (`nvim +terminal`) every
--- other pane uses — an nvim terminal buffer, so Terminal-Normal mode and the
--- tmux `is_vim` navigation work here too. Quitting the omp in it ends the
--- pane: the script takes itself away, the terminal closes, the pane's
--- TermClose autocmd quits nvim, and tmux closes the pane with it. The whole
--- `+terminal …` is one shell word (nvim takes everything after `+` as the Ex
--- command), and tmux runs the pane through the shell, so each layer is quoted
--- for the shell that reads it.
---
--- The invocation itself does not ride on the `:terminal` command line: nvim
--- expands that argument the way an Ex command's file argument is expanded, so
--- a `%` or `#` in it becomes the current / alternate file name (`E499` on an
--- unnamed buffer — the TODO view is one) and a `<cword>`-style span its
--- expansion. The omp argv carries the ticket's title and body, arbitrary text
--- that holds any of them — a title reading `20% off` is enough to fail a
--- launch — so the shell-quoted invocation goes into a script instead, and the
--- Ex command expands only that script's own safe path.
---@param argv string[]
---@return string
local function pane_command(argv)
  local script = vim.fn.tempname()
  vim.fn.writefile({ '#!/bin/sh', table.concat(vim.tbl_map(vim.fn.shellescape, argv), ' '), 'rm -f -- "$0"' }, script)
  return table.concat(vim.tbl_map(vim.fn.shellescape, { 'nvim', '+terminal sh ' .. script }), ' ')
end

--- The omp argv for an interactive instance on `ticket` — the shape the
--- `<prefix> i` panel lists and jumps to. A ticket with a session resumes it
--- (`--session-dir` + `--continue`, full context); one without starts fresh
--- with the ticket prompt. A resumed session keeps the same interactive shape
--- as a launch: it is the user's pane, quit by hand.
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

--- The lines of the Visual selection, leaving Visual mode. The mapping runs
--- while the region is still active: `'v'` is its start and the cursor its
--- end (the plugin's own take_visual, org.agenda.view.mappings).
---@return integer first
---@return integer last
local function take_visual()
  local a, b = vim.fn.line 'v', vim.fn.line '.'
  vim.cmd 'normal! \27'
  return math.min(a, b), math.max(a, b)
end

--- The headlines covered by lines [first, last] of the current buffer, as
--- { bufnr, lnum } in the order they appear. In the agenda / TODO view a
--- rendered entry line is an item, resolved to its source headline; in an
--- org buffer every headline whose line falls in the range — the real
--- headlines behind them when the range is in the `org-entry` preview
--- scratch, whose lines are the entry's own.
---@param first integer
---@param last integer
---@return { bufnr: integer, lnum: integer }[]
local function targets_in_range(first, last)
  local targets = {}
  if vim.bo.filetype == 'orgagenda' then
    local view = require 'org.agenda.view'
    local items = (view.state or {}).line_items or {}
    local seen = {}
    for l = first, last do
      local item = items[l]
      if item and not seen[item] then
        seen[item] = true
        local target = view.resolve_target(item)
        if target then
          targets[#targets + 1] = { bufnr = target.bufnr, lnum = target.lnum }
        end
      end
    end
    return targets
  end
  if vim.bo.filetype == 'org' then
    local bufnr, base = vim.api.nvim_get_current_buf(), 0
    local src, src_line = preview_source()
    if src then
      bufnr, base = src, src_line - 1
    end
    local file = require('org.files').get_buffer(bufnr)
    for _, hl in ipairs(file.headlines) do
      if hl.line >= base + first and hl.line <= base + last then
        targets[#targets + 1] = { bufnr = bufnr, lnum = hl.line }
      end
    end
  end
  return targets
end

--- Reload org files changed on disk under the loaded buffers and re-render
--- the agenda view. The agent writes to the file while nvim holds the
--- buffer, so a reload is what makes the write-back visible -- with the file's
--- stat kept alongside the text (helpers/org/write.lua), so a write from the
--- view does not have to ask about a change the buffer already carries.
function M.sync()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and name:match '%.org$' then
      if #vim.fn.win_findbuf(buf) == 0 then
        write.refresh(buf)
      else
        pcall(vim.api.nvim_buf_call, buf, function()
          vim.cmd 'silent! checktime'
        end)
        -- checktime re-read the file (autoread); a buffer it left modified
        -- keeps the stat it had
        write.remember(buf)
      end
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

--- Launch every `target`: its own :ID: / :OMP_SESSION: link, its NEXT state,
--- its checkpoint and its own omp pane. The buffers are launched in order and
--- the lines within one biggest first, so the property drawer the launcher
--- writes on one entry cannot shift the lines of a ticket still to come.
--- Returns how many instances started.
---@param targets { bufnr: integer, lnum: integer }[]
---@return integer
local function launch_targets(targets)
  table.sort(targets, function(a, b)
    if a.bufnr == b.bufnr then
      return a.lnum > b.lnum
    end
    return a.bufnr < b.bufnr
  end)

  local launched = 0
  for _, target in ipairs(targets) do
    local ticket = ticket_at(target.bufnr, target.lnum, true)
    if ticket then
      checkpoint(ticket)
      if in_tmux() then
        open_pane(ticket)
      else
        open_window(ticket)
      end
      launched = launched + 1
    end
  end
  return launched
end

--- Report a multi-ticket launch: one instance is the ordinary case and says
--- nothing, a fan-out (a container's frontier, a Visual selection) is worth
--- a line.
---@param launched integer
local function notify_launched(launched)
  if launched > 1 then
    notify(('org ai: launched %d tickets'):format(launched))
  end
end

--- `<leader>ai` in an org or orgagenda buffer: commit the project's pending
--- work (the revert point for the run), then start omp on the headline. In an
--- open capture buffer the capture is finished first (target_at_cursor), so
--- the ticket is the entry just stored. On a headline with open work under
--- it -- a group node, the map of a live expedition -- the run fans out to
--- the frontier below it, one instance each (expand_target), the containers
--- themselves untouched.
function M.launch()
  local bufnr, lnum = target_at_cursor(true)
  if not bufnr then
    return
  end
  local launched = launch_targets(expand_target(bufnr, lnum))
  notify_launched(launched)
  M.sync()
end

--- The same launch applied to one headline already in hand: the ticket at
--- `lnum` of `bufnr` gets exactly what `<leader>ai` gives the headline at
--- point -- its own :ID: / :OMP_SESSION: link, its NEXT state, its checkpoint
--- and its own omp pane. Unlike the mapping, the headline is launched itself
--- and never fanned out to the frontier below it: the caller has already
--- decided which headline, and the text it wrote (a note) sits on that one.
--- This is what a note on a TEST entry triggers (helpers/org/notes.lua).
---@param bufnr integer
---@param lnum integer
function M.launch_at(bufnr, lnum)
  notify_launched(launch_targets { { bufnr = bufnr, lnum = lnum } })
  M.sync()
end

--- `<leader>ai` over a Visual selection: the Visual-mode shape of M.launch.
--- Every entry the selection covers is launched exactly as it would be on
--- its own — its own :ID: / :OMP_SESSION: link, its NEXT state, its
--- checkpoint and its own omp pane; a selected container fans out to the
--- frontier below it the same way (so a covered ancestor and a covered
--- descendant both resolve to the descendant's own ticket, which the `seen`
--- set collapses into one). The entries are launched bottom-up, so the
--- property drawer the launcher writes on one entry cannot shift the lines of
--- another still to come, and a headline reached twice (a container and one
--- of its own leaves both covered) is still one ticket.
function M.launch_range()
  local first, last = take_visual()
  local targets = targets_in_range(first, last)
  if #targets == 0 then
    notify('org ai: no entries in the selection', vim.log.levels.WARN)
    return
  end

  local expanded, seen = {}, {}
  for _, target in ipairs(targets) do
    for _, sub in ipairs(expand_target(target.bufnr, target.lnum)) do
      local key = sub.bufnr .. ':' .. sub.lnum
      if not seen[key] then
        seen[key] = true
        expanded[#expanded + 1] = sub
      end
    end
  end

  notify_launched(launch_targets(expanded))
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
