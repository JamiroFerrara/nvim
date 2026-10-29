-- OMP on an org ticket: `<leader>ai` in the TODO view (or an org buffer)
-- opens an `omp` instance for the headline at point, seeded with the ticket's
-- :ID: and file. Over a Visual selection it is that same launch applied to
-- every entry the selection covers (M.launch_range); a launch that covers
-- several tickets is one instance, the batch below.
--
-- A launch that covers several tickets is one instance, not one each: the
-- container fan-out, a Visual selection and the level a climb rises to are
-- all handled by a single orchestrator omp (`open_orchestrator`) with the
-- omp-orchestrator skill appended, handed every ticket in one message. Its
-- subagents do the working, so a frontier of eighteen costs one omp process
-- and one tmux pane instead of eighteen -- which is what made a launch on a
-- big container crawl the machine. The tickets still get everything a
-- single-ticket launch gives them: their own :ID: / :OMP_LAUNCH:, the claim,
-- the project checkpoint, and an :OMP_SESSION: linking them to the batch's
-- session (`orchestrators/<project>`, resolved by `session_dir`).
--
-- A launch lands on what is takeable under the headline, not on the headline
-- itself: the frontier -- the tickets open with nothing open below them
-- (expand_target's `frontier`) -- because a ticket nested under another is
-- blocked by it (skill://wayfinder/org-tracker.md: the vault has no
-- dependency relationship of its own, so "where a ticket sits is its
-- blocking, children first"). A headline with open work under it is
-- therefore a container, not a ticket of its own: the launch walks down
-- through it, past every open ticket still waiting on its own subtree, to
-- the leaves that block them -- one instance when the frontier is one ticket,
-- one orchestrator batch when it is several -- and the containers themselves
-- are stamped with nothing. Launching the root of a charted chain
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
-- A ticket whose run is still on it takes the note itself: helpers/org/notes.lua
-- and the board's note box both hand the text to M.deliver_note first, which
-- types it into the instance that already holds the ticket (the ticket's own
-- pane, or the project orchestrator that batch-launched it) -- the work in
-- flight reads it as the user's next turn instead of a second instance
-- starting beside it on the same headline.
--
-- With nothing running the note is the usual case again. On an entry in TEST
-- it starts the same run without the key: the entry is waiting on the user's
-- validation, so a note there is their answer to it and the headline goes to
-- M.launch_at once the note is stored -- the agent reads the note as the
-- ticket's new body. That launch claims the entry back to `NEXT`
-- (M.launch_at's `claim`): the hand-back the last run wrote has been answered,
-- so what stands is a run on the ticket again, not a change still awaiting
-- validation. Every other state just stores the note.
--
-- Layout: the first launch splits the nvim pane once with a vertical divider
-- (`split-window -h`, omp on the right). Once anything already sits beside
-- nvim, every later launch opens its own tmux window inserted after the
-- current one (`new-window -a`, the `prefix+n` equivalent) instead of stacking
-- panes in the right column, so each instance gets a full window. Each pane
-- carries the ticket's :ID: in its `@omp_ticket` pane option (the "already
-- running?" lookup) plus its window name / title; an orchestrator pane carries
-- its session key in `@omp_orchestrator` instead, which is both the lookup for
-- a further batch of the same project and the guard on the pane's own close
-- (the skill's last act). A batch handed to a project whose orchestrator is
-- already running is typed into that instance (`deliver`) rather than started
-- a second time. Splits and windows are created detached (`-d`): the launch
-- never moves the active pane or window off nvim, so the cursor stays put.
--
-- Talk is the other way in, and it gets one instance: words that come from
-- outside the board -- the voice card on the dashboard, `:OrgVoice`,
-- `:OrgVoiceSay` -- are handed to a single talking instance (`TALK_KEY`, its
-- own session, marked `@omp_orchestrator` like a project's batch and found by
-- that mark the same way). It is a router, not a worker: it answers what is a
-- question, and for work it files a ticket and starts the run on it (`M.talk`
-- -- the same `preset_ticket` write and `launch_targets` dispatch a keypress
-- gets, so a spoken ticket is the ordinary ticket on the board), then quotes
-- the launcher's one line back. One instance keeps one conversation, which is
-- what lets "that one too" mean anything, and the org write lands before the
-- run is dispatched, so the board shows the work started as soon as the words
-- are filed.
--
-- The pane runs `nvim "+terminal sh <script>"`, the same shape as the tmux
-- default-command (`nvim +terminal`) every other pane uses, so the instance
-- lives in an nvim terminal buffer and navigates like the rest of the session
-- (Terminal-Normal vim keys, tmux `is_vim` pane moves); the script holds the
-- omp invocation, which `:terminal` would otherwise mangle, `%` and `#` in a
-- ticket title first of all.
--
-- The launcher owns the start of the run: it puts an :ID: on the headline
-- (reusing one already there), claims it (`NEXT`) when the ticket is the
-- launcher's to claim -- an untouched one (`TODO`, or no keyword at all), one
-- parked on the user (`PEND`: pressing the key there is the user coming back
-- to it) and one they already closed (`DONE`: the work is finished, so a
-- launch on it is a fresh run on the same headline) -- counts the launch in
-- the drawer, saves the file, and only then starts omp. A state a run wrote
-- as its own outcome (`TEST` awaiting the user's validation, `WARN`) stands:
-- relaunching is not a reason to erase it, and such a state goes back to
-- `NEXT` only when the launch is the user's own answer to the hand-back (the
-- note on a TEST entry, M.launch_at's `claim`). The launch number rides along
-- (`:OMP_LAUNCH:`), and the message omp starts with
-- says which launch this is, so a run that finds its own unanswered round in
-- the ticket can tell a relaunch from an answer instead of reading silence as
-- consent (the relaunch rule is the omp-org-ticket skill's).
--
-- A launch whose buffer is stale is refused: an agent's write-back lands on
-- disk while nvim holds the file, so writing the state back from a buffer
-- that never saw it would drop it (helpers/org/write.lua, `M.stale`), and an
-- unforced write there is the W12 question nothing answers.
--
-- Before that hand-off it also commits the ticket's project's pending
-- *tracked* work (helpers/org/project.lua's
-- `#+PROJECT_DIRS:` claims, one commit per repo, never a push): that commit
-- is the revert point, so a run that goes wrong is undone with
-- `git reset --hard` back to it instead of unpicking a dirty tree. The
-- untracked files are left out of it -- a `reset --hard` never touches them
-- -- because a repo can hold a pile of them (a scratch checkout, a clone)
-- and staging those is what froze the UI: the checkpoint runs inside the
-- mapping, on the ticket's keypress (`snapshot`'s own note). The commit is
-- made with `--no-verify` for the same reason: a repo's own `pre-commit`
-- gate is the user's, over the user's commits, and running it here would
-- hold the UI for as long as the gate takes (the waypoint repo's `make
-- check` is a build and a format check, 21s measured) while its verdict can
-- only lose the revert point.
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
-- The tree moves up from there, and it rises a level at a time. A ticket with
-- a ticket above it is offered the climb at the end of its run (M.climb_up):
-- the ordinary launch applied to the headline it hangs under, narrowed to the
-- tickets no run has touched yet (`TODO`). So the climb starts what the level
-- above leaves takeable -- that headline itself when nothing under it is open,
-- and every ticket left open and takeable under it otherwise (a sibling this
-- run did not close, a ticket charted into that subtree since the level was
-- last launched) -- where the single launch it replaces took only the one,
-- and a level of several is one orchestrator batch. A ticket a run already
-- took is left where it stands:
-- `NEXT` is a run on it, `TEST` a change awaiting validation, `PEND` the
-- user's, `WARN` a failure. The headline above is the one exception, and only
-- at `NEXT`: nothing under it open, that claim is the level's own marker while
-- its work ran -- the map of an expedition reads `NEXT` exactly while its
-- tickets are open -- so the climb rising onto it is what launches the map
-- pass, and a run still holding it makes the launch refuse instead. That is
-- also what keeps a frontier launched
-- together from racing for the parent: the leaves still in flight are `NEXT`,
-- so the run that finds untouched work left below the parent is the last one
-- to finish, and the climb starts there.
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

-- the skill appended instead when a launch covers several tickets: the same
-- rules applied to subagents, one omp process for the whole batch
local ORCHESTRATOR = vim.fn.expand '~/.agents/skills/omp-orchestrator/SKILL.md'

--- The session key of the talking instance: the one omp every line spoken
--- into the renderer is handed to (the dashboard's voice card,
--- `helpers/org/voice.lua`; `:OrgVoice`; `:OrgVoiceSay  {text}`). Its own key,
--- apart from both kinds a launch already names -- a ticket's (`tickets/<id>`)
--- and a project's batch orchestrator (`orchestrators/<project>`) -- so a
--- speech never starts a second instance and no launch can look one up by
--- mistake. The slash puts its session under `<agent dir>/talk/one`, where the
--- runs window reads its transcript like any other run's.
local TALK_KEY = 'talk/one'

--- How many of the talking instance's spec files are kept: the words of the
--- last lines said, which outlive the editor (Open_Prompt's own note).
local SPECS_KEPT = 200

--- What the talking instance is told once, as its system prompt: it is the
--- one instance the renderer's words reach, and its whole job is to sort them
--- -- answer a question here, file work as a ticket and start that ticket's
--- run (`M.talk`), which is the feedback the user wants as soon as they stop
--- talking. It never does the work itself: the run the ticket starts does.
--- The vault path is read from the config at the time the instance opens, so
--- the rules name the vault this nvim is looking at.
---@return string
local function talk_rules()
  local org_dir = '~/org'
  pcall(function()
    local cfg = require('org.config').opts
    if cfg and cfg.org_directory then
      org_dir = cfg.org_directory
    end
  end)
  org_dir = vim.fn.expand(org_dir)
  return table.concat({
    'You are the talking instance of the org renderer: the one omp that every line spoken or typed into it',
    'is handed to (the voice card on the dashboard, :OrgVoice, :OrgVoiceSay). There is one of you, and there',
    'stays one: the launcher hands a new line to this session instead of starting another.',
    '',
    'You do not work tickets, and you never close this pane. A run does the work; your job is to sort what',
    'the user said and get work onto the board immediately, so that the board shows it started as soon as',
    'they stop talking.',
    '',
    'The vault is at ' .. org_dir .. ', and its rules are in ' .. org_dir .. '/WORKFLOW.org.',
    '',
    'Each message is one thing the user said: the words, the view they were said on, and the path of a spec',
    'file holding the same words as JSON. Sort the words into one of these, and act in the same turn:',
    '',
    '- A question: answer it here, in two or three lines. No file, no run.',
    '- A remark to you: say what you take from it, one line, and stop.',
    '- Work: file it and start it, in that order, with one command --',
    '',
    "    nvim --headless -c \"lua require('helpers.org.ai').talk('<spec path>')\" -c 'qa!'",
    '',
    '  The spec already names the org file the words belong to, and -- when the dashboard had an entry',
    '  highlighted -- the entry they hang under, by its :ID:. When the spec names no file, the words did not',
    '  say where they belong: pick the project file they belong to (the WORKFLOW rules say how a project is',
    '  filed) and pass it as the second argument --',
    '',
    "    nvim --headless -c \"lua require('helpers.org.ai').talk('<spec path>', '<file>')\" -c 'qa!'",
    '',
    '  The command writes the words as a ticket -- the headline, its :ID:, its body, then the launch every',
    '  other launch is: the state to NEXT, the session link, the checkpoint, a pane of its own -- and prints',
    '  one line saying what it wrote and where the run lives. Nobody writes org text by hand here: the',
    '  command is the write, and the run it starts is what reads it.',
    '',
    '  Words that are plainly two jobs are two tickets: run the command for each, one after the other.',
    '  Never do the work the words ask for: the run the command starts is the worker, and you are not.',
    '',
    'Reply short. When the command printed its line, quote that line and nothing else; when you answered a',
    'question, the answer is the whole reply. You keep the conversation, so a later "that one too" or "no,',
    'the other project" is answered from what came before -- the spec files are the record of what was said.',
  }, '\n')
end

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

--- The headline property counting the launches of a ticket. The launcher
--- writes it on every launch (1, 2, 3 …) and the launch message carries the
--- number, so a run reading its own ticket can tell the first launch from a
--- relaunch — the one case where the ticket may already hold the run's own
--- unanswered round.
local LAUNCH_PROP = 'OMP_LAUNCH'

--- The keywords a launch of the user's own overwrites with `NEXT`: the
--- untouched ticket (`TODO`, and an unkeyworded headline), one parked on the
--- user (`PEND`) -- pressing `<leader>ai` on a pending entry is the user
--- coming back to it, so the run the launch starts is what the entry holds --
--- and one already closed (`DONE`): its work is finished and validated, so a
--- launch on it is a new run on the same headline, and the board says so
--- instead of leaving a closed ticket running. `TEST` (a change handed back
--- for their validation) and `WARN` (a run that failed) are a run's own
--- outcome: those go back to `NEXT` only on the caller's record that it was
--- answered (ticket_at's `claim`, the note on a `TEST` entry).
local CLAIMABLE = { TODO = true, PEND = true, DONE = true }

--- The keywords the climb starts below the level above: only what no run has
--- touched. The climb is the run's own act, not the user's keypress, so a
--- `PEND` (the user's to answer) and a `TEST` (theirs to validate) are left
--- where they stand -- the level above waits for the user, not for this run.
--- `CLAIMABLE` is the launch's own set; this one is the climb's, and the two
--- are deliberately apart. The level above itself is read at `RISING`.
local UNTOUCHED = { TODO = true }

--- The keyword the climb takes the level above at on top of `UNTOUCHED`: a
--- `NEXT` on the parent itself, when nothing under it is open. A launch never
--- claims a headline that holds open work below it -- it fans out to that
--- work (`expand_target`) and the containers are stamped with nothing -- so a
--- `NEXT` there is not a run in flight: it is the claim the level carries
--- while the work under it runs (an expedition's map reads `NEXT` exactly
--- while its tickets are open), and the climb is what rises onto it once they
--- close. The level itself only: a `NEXT` sibling *below* the parent is a run
--- on that sibling, and the climb leaves it where it stands, which is what
--- keeps a frontier launched together from racing for the parent.
local RISING = { NEXT = true }

--- The session key linking a ticket to the agent that works it: the
--- :OMP_SESSION: link when the headline carries one; a ticket that never
--- launched falls back to its :ID:, which is the link a launch would have
--- written — so a resume here and a later launch land in the same directory.
---@param ticket OrgTicket
---@return string|nil
local function session_key(ticket)
  local key = ticket.session and ticket.session:match '%S' and vim.trim(ticket.session)
  if not key or key == '' then
    key = ticket.id and ticket.id:match '%S' and ticket.id
  end
  return key
end

--- The directory holding the session `key` names. A key carrying a slash is a
--- path of its own under the agent directory (`orchestrators/<project>`, the
--- batch orchestrator of a multi-ticket launch); a bare key is one ticket's
--- session (`tickets/<key>`). That keeps the :OMP_SESSION: a plain key for the
--- per-ticket launches already on disk while letting a batch point every
--- ticket at the one session that worked them all.
---@param key string
---@return string
local function session_dir(key)
  return agent_dir() .. '/' .. (key:find '/' and key or ('tickets/' .. key))
end

-- where a run keeps its transcript, for the views that follow one live
-- (helpers/org/web/live.lua)
M.agent_dir = agent_dir
M.session_dir = session_dir

---@class OrgProject
---@field dir string the directory the project is keyed on
---@field key string session key of the project's orchestrator (a path under the agent dir)
---@field name string short name for a window title

--- The project the ticket at `lnum` of `file` belongs to: the first directory
--- its file claims there (helpers/org/project.lua's `#+PROJECT_DIRS:`), else
--- the directory the file lives in. One orchestrator serves one such project,
--- keyed the way the session directories are named.
---@param file string the ticket's org file
---@param lnum integer the line of one of its headlines
---@return OrgProject
local function project_of(file, lnum)
  local dirs = require('helpers.org.project').dirs(file, lnum)
  local dir = vim.fs.normalize(dirs[1] or vim.fs.dirname(file))
  local slug = (dir:gsub('[^%w]+', '-'):gsub('^%-+', ''):gsub('%-+$', ''))
  return { dir = dir, key = 'orchestrators/' .. slug, name = vim.fn.fnamemodify(dir, ':t') }
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
---@field launch integer how many times this ticket has been launched (1 on the first)
---@field state string|nil the keyword the launcher leaves the headline in
---@field claimed boolean whether this launch wrote that keyword (NEXT) or found it
---@field note string|nil the user's newest turn, read out of the body (`user_turn`), on one line
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

--- `text` on one line: every run of whitespace -- the newlines of a note the
--- user typed into the entry included -- becomes one space, the ends trimmed.
--- Everything that carries arbitrary text into a launch message goes through
--- it: the message is a single line, because the pane runs it through
--- `nvim "+terminal …"` and `pane_command`'s script would break on a newline
--- inside a `shellescape`d argv item.
---@param text string|nil
---@return string
local function one_line(text)
  return vim.trim((text or ''):gsub('%s+', ' '))
end

--- The block header of an entry body: an inactive timestamp and a dash rule,
--- which both the note writer (helpers/org/notes.lua) and the omp write-back
--- put over every turn. The text before the timestamp tells them apart: the
--- agent's carries the 🤖 icon, the user's is empty.
local HEADER = '^%s*(.-)%[%d%d%d%d%-%d%d%-%d%d[^%]]*%]%s*%-%-%-%-%-'

--- The user's newest turn in `hl`'s body, when the body ends on one: the last
--- block of the entry is a note the user wrote (a plain header, no 🤖) and an
--- agent's block (🤖) came before it. The body is a chronological log -- the
--- capture that created the entry, then every turn in order
--- (helpers/org/notes.lua) -- so that block is the last thing the user said,
--- and the launch message carries it (`prompt`, `batch_prompt`): a run handed
--- only the headline has to guess which block it was started for, and a log
--- that mixes hand-backs with fresh notes makes that a guess.
---
--- nil when the newest block is the agent's own (nothing new was said) and
--- when the body never held an agent block (a ticket no run has worked yet,
--- whose only block is the capture that describes it).
---@param file org.File
---@param hl org.Headline
---@return string|nil note
local function user_turn(file, hl)
  local lines = file.lines
  local last, worked = nil, false
  for i = hl.line + 1, hl.body_end do
    local lead = lines[i] and lines[i]:match(HEADER)
    if lead then
      if lead:find('🤖', 1, true) then
        worked, last = true, nil
      else
        last = i
      end
    end
  end
  if not (last and worked) then
    return nil
  end
  local text = {}
  for i = last + 1, hl.body_end do
    text[#text + 1] = lines[i] or ''
  end
  local note = one_line(table.concat(text, ' '))
  return note ~= '' and note or nil
end

--- The ticket for the headline at `lnum` of `bufnr`, in an orgagenda or an
--- org buffer. With `mutate` set (the launch) a missing :ID: is created, the
--- state is claimed (NEXT) when the ticket is CLAIMABLE, the buffer saved;
--- without it (the jump) nothing is written -- the headline is only read.
---
--- `claim` widens the claim past CLAIMABLE: the caller has read the state
--- itself and knows it was consumed, so the run starting now is what the entry
--- holds. M.launch_at is the one caller that does -- the note it was handed
--- answered the `TEST` hand-back the entry stood in, so the entry goes back to
--- `NEXT` for the run that reads the note.
---
--- `link` is the key of the session that will work the ticket, when the
--- caller already knows it: a ticket launched in a batch is the project
--- orchestrator's, and its :OMP_SESSION: is that session's key rather than its
--- own :ID: -- a key the run that worked it before had set is replaced,
--- because the property names the session that works the ticket now.
---
--- `origin` is who fired the launch, for the message the run opens with
--- (`prompt`): `<leader>ai` unless a caller says otherwise.
---@param bufnr integer
---@param lnum integer
---@param mutate boolean
---@param claim? boolean
---@param link? string the session key to link the ticket to
---@param origin? string
---@return OrgTicket|nil
local function ticket_at(bufnr, lnum, mutate, claim, link, origin)
  local file = require('org.files').get_buffer(bufnr)
  local hl = file:headline_on(lnum)
  if not hl then
    notify('org ai: not under a headline', vim.log.levels.WARN)
    return nil
  end

  local id = require('org.id').get { bufnr = bufnr, lnum = hl.line }
  local missing_id = not (id and id:match '%S')
  local session = hl:get_property(SESSION_PROP, false)
  local launch = tonumber(hl:get_property(LAUNCH_PROP, false) or '') or 0
  local state = hl.todo
  local claimed = false
  -- what the user said last, read off the body itself: it is the turn this
  -- launch answers, whoever fired it (notes.lua's note on a TEST entry, the
  -- key pressed after the user parked the entry and wrote, a level climbing)
  local note = user_turn(file, hl)
  if mutate then
    -- An agent's write-back lands on disk while nvim holds the file; writing
    -- the drawer and the state into a buffer that never saw it would drop it
    -- (helpers/org/write.lua, `M.stale`), and the unforced write that follows
    -- is the W12 question nothing answers -- a mapping, and the headless
    -- climb, would hang on it. Reload what can be reloaded and refuse the
    -- launch otherwise: the user saves or reloads, then launches.
    if write.stale(bufnr) then
      notify(
        'org ai: ' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':t') .. ' changed on disk — save or :e! before launching',
        vim.log.levels.WARN
      )
      return nil
    end

    if missing_id then
      id = require('org.id').get_create { bufnr = bufnr, lnum = hl.line }
    end

    -- Link the ticket to its omp session: the key is the :ID: at the first
    -- launch, written to the drawer, so a later launch resumes the same
    -- session instead of starting fresh -- or the caller's key, when it knows
    -- which session will work the ticket (a batch's orchestrator).
    if link and session ~= link then
      session = link
      require('org.properties').entry_put(bufnr, hl.line, SESSION_PROP, session)
    elseif not (session and session:match '%S') then
      session = id
      require('org.properties').entry_put(bufnr, hl.line, SESSION_PROP, session)
    end

    launch = launch + 1
    require('org.properties').entry_put(bufnr, hl.line, LAUNCH_PROP, tostring(launch))

    -- Claim the ticket: `NEXT` means "a run is on this", which is what a
    -- launch holds for an untouched ticket (`TODO`), for one parked on the
    -- user (`PEND`) -- pressing the key on a pending entry is the user coming
    -- back to it -- and for one already closed (`DONE`), where the launch is
    -- a fresh run on a finished headline (CLAIMABLE). The states a run's own
    -- outcome lives in (`TEST`, `WARN`) are left standing: the run that
    -- follows reads the state and the launch number, and the omp-org-ticket
    -- skill decides what a relaunch means. Unless the caller says the state
    -- it found was answered (`claim`, M.launch_at's note): then the entry is
    -- a run's again whatever it held. `force` skips blockers so the claim is
    -- deterministic whatever the map looks like.
    if state == nil or claim or CLAIMABLE[state] then
      -- Leaving a done state takes its `CLOSED:` stamp with it: org records
      -- it when the entry closes, so it describes a ticket nobody works.
      -- org.todo only drops it when org's own logging is on, and this vault
      -- logs nothing, so the launcher clears it here -- otherwise the
      -- reopened headline reads `NEXT` over the date it was closed.
      local was_done = state ~= nil and file.settings.todo:is_done(state)
      local result = require('org.todo').change_state({ bufnr = bufnr, lnum = hl.line }, 'NEXT', { force = true })
      state, claimed = 'NEXT', true
      if was_done and result and result.lnum then
        local reopened = file:headline_on(result.lnum)
        -- Only the single planning line org writes is edited: a stamp spread
        -- over lines of its own would be left behind by that edit, so it
        -- stays and the entry is not made worse than it was.
        local lines, l, count = file.lines, result.lnum + 1, 0
        while lines[l] and lines[l]:match '^%s*(SCHEDULED|DEADLINE|CLOSED):' do
          count, l = count + 1, l + 1
        end
        if count <= 1 and reopened and reopened.planning and reopened.planning.closed then
          require('org.edit').set_planning(bufnr, result.lnum, 'closed', nil)
        end
      end
    end
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if mutate then
    -- The write may not ask: `M.stale` above proved the buffer fresh when it
    -- read it, but the drawer and the claim are written in between, and
    -- another writer (an agent working the same file) can land in that
    -- window. `no_prompt` then refuses the write instead of putting nvim's
    -- W12 question up -- a question a mapping freezes on, and the headless
    -- climb has nobody to answer. The launch aborts: a run whose ticket file
    -- lacks the drawer and the claim it just wrote is not worth starting.
    local saved = write.save(bufnr, { no_prompt = true })
    if not saved then
      notify('org ai: ' .. vim.fn.fnamemodify(path, ':t') .. ' changed on disk — save or :e! before launching', vim.log.levels.WARN)
      return nil
    end
  end

  return {
    bufnr = bufnr,
    lnum = hl.line,
    id = id,
    session = session,
    launch = launch,
    state = state,
    claimed = claimed,
    note = note,
    origin = origin,
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

--- The headlines a launch on `hl` covers: the frontier below it (see
--- `frontier`), or `hl` itself when it has nothing open
--- under it. A headline with open work below it is a container, not a ticket
--- of its own: launching its root would stamp the container, whose :ID: /
--- NEXT / hand-back describe the whole subtree, while the ticket the run
--- could work -- the leaf blocking it -- stayed untouched. So a launch walks
--- down to those leaves, which is what makes launching a charted chain start
--- the task at its bottom; once that task is done the ticket above it has
--- nothing open below it in turn, and the next launch lands on that one --
--- the frontier climbing the chain as its leaves close. A leaf ticket, and
--- the map of an expedition whose tickets are all closed, has no frontier
--- below it and is launched itself. The leaves are distinct headlines, so no
--- two instances claim the same one.
---@param hl org.Headline
---@return org.Headline[]
local function expand_headline(hl)
  local leaves = {}
  frontier(hl, leaves)
  if #leaves == 0 then
    return { hl }
  end
  return leaves
end

--- The same expansion as { bufnr, lnum } in the order the headlines appear,
--- for a launch that has an entry rather than its headline in hand: the entry
--- at `lnum` of `bufnr` is `expand_headline`'d, and an entry with no headline
--- under the cursor is passed through unchanged.
---@param bufnr integer
---@param lnum integer
---@return { bufnr: integer, lnum: integer }[]
local function expand_target(bufnr, lnum)
  local file = require('org.files').get_buffer(bufnr)
  local hl = file and file:headline_on(lnum)
  if not hl then
    return { { bufnr = bufnr, lnum = lnum } }
  end
  local targets = {}
  for _, leaf in ipairs(expand_headline(hl)) do
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
---
--- The commit carries the *tracked* work, not untracked files: the caller
--- runs inside a mapping, and a repo that is a scratch checkout -- a personal
--- `bin` holding clones, hundreds of thousands of files -- would be staged
--- and hashed **whole** by `add -A`, gigabytes of it, while nvim's UI waits
--- (this repo: `git add -A -n` alone, no objects written, took 23s over
--- 61k paths). Nothing is lost for the revert point: `git reset --hard`
--- never touches a file the index does not hold, so an untracked file
--- survives the reset whether or not the checkpoint committed it. Work the
--- user has already staged -- a new file they `git add`ed -- rides along in
--- the commit, `-a` adding the tracked modifications to it.
---
--- And it is made with `--no-verify`: a repo's `pre-commit` gate is the
--- user's, over the user's own commits, and running it here holds the UI for
--- as long as the gate takes -- the waypoint repo's `make check` is a `dotnet
--- build` + `dotnet format` (measured: 21s inside the keypress) and minutes
--- on a cold cache -- while its verdict can only *lose* the revert point (a
--- failing gate refuses the commit, and the launch goes on without one).
--- A snapshot of work the user already wrote is not a change to be gated.
---@param root string
---@param subject string
---@return boolean|nil committed, string|nil err
local function snapshot(root, subject)
  local status = git(root, { 'status', '--porcelain', '--untracked-files=no' })
  if status.code ~= 0 then
    return nil, git_error(status)
  end
  if not status.stdout:match '%S' then
    return false
  end
  local commit = git(root, { 'commit', '--quiet', '--no-verify', '-a', '-m', subject })
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
  local prefix = ' chore(omp): checkpoint before '
  local summary = one_line(title)
  local room = 72 - vim.fn.strchars(prefix)
  if vim.fn.strchars(summary) > room then
    summary = vim.fn.strcharpart(summary, 0, room - 1):gsub('%s+%S*$', '') .. '…'
  end
  return prefix .. summary
end

--- Commit the pending *tracked* work of every repo the ticket's project
--- claims — the repository as the user left it, before the agent touches it.
--- This is the revert point: a run that goes wrong is undone with
--- `git reset --hard` to it, so it costs little. Never a push, and never a
--- commit on a clean tree (`snapshot` for what "pending" leaves out, and
--- why). The ticket's file names the repos through its `#+PROJECT_DIRS:`
--- claims (helpers/org/project.lua); a repo that will not commit is reported
--- and the launch goes on.
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

--- The message omp starts with: the ticket's identity, which launch this is,
--- the state the launcher left the headline in, and whether the :ID: is the
--- launcher's to remove. One line, so it survives shell quoting in the pane.
---
--- The state line says what the launcher did, not what it wishes: a launch
--- claims the ticket (`NEXT`) when it is untouched, parked on the user
--- (`PEND` -- the keypress there is the user coming back) or closed
--- (`DONE` -- a new run on a finished headline), and leaves what a run itself
--- wrote (`TEST` awaiting validation, `WARN`), so the run has to read that
--- rather than assume it was reset. The launch number is the other half of
--- the same fact: `#2` on a ticket whose body already holds this skill's own
--- round is a relaunch, and the skill says what a relaunch means.
---
--- A ticket whose body ends on the user's turn (`ticket.note`, `user_turn`)
--- carries that turn's text in the message as well: the body is a log of
--- every turn -- the capture, then notes and hand-backs in the order they
--- happened -- and a run left to guess which block is the new one answers an
--- older one. It is one line by then (`one_line`).
---@param ticket OrgTicket
---@return string
local function prompt(ticket)
  local state = ticket.state and ('`' .. ticket.state .. '`') or 'none'
  local parts = {
    'Org ticket launched by ' .. (ticket.origin or 'nvim <leader>ai') .. '.',
    'File: ' .. ticket.file .. '.',
    'ID: ' .. ticket.id .. ' (permanent: the knowledge base links this ticket by it; never remove it).',
    'Title: ' .. ticket.title .. '.',
    'Launch: #' .. ticket.launch .. '.',
    'State: ' .. state .. (ticket.claimed and ' (the launcher claimed it).' or ' (left as the last run left it).'),
  }
  if ticket.note then
    parts[#parts + 1] = 'Note the user wrote on this ticket, the one this launch answers: "' .. ticket.note .. '".'
  end
  parts[#parts + 1] = 'Follow the omp-org-ticket rules appended to your system prompt.'
  return table.concat(parts, ' ')
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
---
--- A ticket whose :OMP_SESSION: already names a project orchestrator (a batch
--- launched it) is a batch of one instead: the same session, the orchestrator
--- rules and a one-ticket message, `orchestrator_argv`, so the launch and the
--- session it resumes agree on which rules they are running under.
---@param ticket OrgTicket
---@return string[]

--- The message a batch orchestrator starts with — or is handed a further batch
--- through, `deliver`. It opens with omp's `orchestrate` keyword, so the
--- instance runs under omp's own orchestration contract instead of the
--- single-ticket one, then gives the identity the omp-org-ticket rules need,
--- one line each, in the order they are to be worked, plus the session key its
--- pane carries (the guard on the pane's own close). One line, like `prompt`: the
--- pane runs it through `nvim "+terminal …"`, which executes the whole
--- `+{cmd}` as Ex commands, so a newline would split it into a second (invalid)
--- command, and `tmux send-keys` types it into an omp prompt as one message.
---@param tickets OrgTicket[]
---@param project OrgProject
---@return string
local function batch_prompt(tickets, project)
  local ordered = vim.list_slice(tickets)
  -- the launcher resolves them bottom-up (writing a drawer shifts the lines
  -- below it), but the message reads top-down: the order the file holds them
  table.sort(ordered, function(a, b)
    return a.lnum < b.lnum
  end)
  local parts = {
    -- omp's own orchestration contract, by its magic keyword: standalone and
    -- lowercase, it makes omp append the notice that has the agent dispatch
    -- subagents, verify what came back and stop narrating -- the rules of the
    -- harness the user runs, before any ticket is looked at
    'orchestrate.',
    ('Org tickets launched by nvim <leader>ai: %d of them, one batch.'):format(#ordered),
    'File: ' .. ordered[1].file .. '.',
    'Orchestrator session key: ' .. project.key .. ' (this pane carries it in its @omp_orchestrator option; it is what the last step of the rules closes).',
    'Tickets, in order:',
  }
  local list = {}
  for i, ticket in ipairs(ordered) do
    local state = ticket.state and ('`' .. ticket.state .. '`') or 'none'
    list[#list + 1] = ('%d. "%s" (:ID: %s, launch #%d, state %s).'):format(i, ticket.title, ticket.id, ticket.launch, state)
  end
  parts[#parts + 1] = table.concat(list, ' ')
  -- a note is the user's newest turn on that one ticket (`user_turn`, read
  -- off the entry's own body), carried here because the batch's rules work
  -- from the message rather than from a body they were pointed at
  for i, ticket in ipairs(ordered) do
    if ticket.note then
      parts[#parts + 1] = ('Note the user wrote on ticket %d, the one this launch answers: "%s".'):format(i, ticket.note)
    end
  end
  parts[#parts + 1] = 'Follow the omp-orchestrator rules appended to your system prompt.'
  return table.concat(parts, ' ')
end

--- The omp argv of a project's batch orchestrator: its session directory, the
--- orchestrator rules, and the batch message. `--continue` resumes the
--- project's orchestrator session when one exists, so a later batch of the same
--- project starts from what the earlier one learned. A nil `message` opens the
--- session without a batch — what the jump does when it finds no orchestrator
--- running.
---@param key string the orchestrator session key
---@param message string|nil
---@return string[]
local function orchestrator_argv(key, message)
  return session_argv(key, ORCHESTRATOR, message)
end

--- The argv of an instance that lives in `key`'s session under `rules`: the
--- session directory (`--continue` where it exists, so a later message lands
--- in what the instance already knows), the rules appended to its system
--- prompt, and the message.
---@param key string the session key
---@param rules string the system prompt appended
---@param message string|nil
---@return string[]
local function session_argv(key, rules, message)
  local dir = session_dir(key)
  local argv = { 'omp', '--session-dir', dir }
  if has_session(dir) then
    argv[#argv + 1] = '--continue'
  end
  argv[#argv + 1] = '--append-system-prompt'
  argv[#argv + 1] = rules
  if message then
    argv[#argv + 1] = message
  end
  return argv
end

local function orchestrator_argv(key, message)
  return session_argv(key, ORCHESTRATOR, message)
end

--- The file the talking rules are written to before an instance reads them.
--- `--append-system-prompt` takes a path (a single-line value that names a
--- file is read as that file), and it has to: the argv is shellescaped into
--- the pane's script, and a newline in an argument becomes a NUL there, which
--- ends the argument at the first stanza -- omp would get one mangled line of
--- the rules and none of the rest. So the rules are a file, rewritten from
--- `talk_rules` on every open, and the argv only ever carries its path.
---@return string
local function talk_rules_path()
  local path = vim.fs.dirname(session_dir(TALK_KEY)) .. '/rules.md'
  pcall(vim.fn.mkdir, vim.fs.dirname(path), 'p')
  pcall(vim.fn.writefile, vim.split(talk_rules(), '\n', { plain = true }), path)
  return path
end

--- The omp argv of the talking instance: its one session, the talking rules
--- (written out first, `talk_rules_path`), and the words. `--continue` resumes
--- the same session on every later line, which is what makes it one instance
--- with one conversation instead of one per utterance. A nil `message` opens
--- the session alone.
---@param message string|nil
---@return string[]
local function talk_argv(message)
  return session_argv(TALK_KEY, talk_rules_path(), message)
end

local function omp_argv(ticket)
  local key = session_key(ticket)
  if key and key:find '/' then
    -- the ticket already belongs to a project orchestrator session (a batch
    -- launched it): the single launch is a batch of one, under that session's
    -- own rules, so the two never disagree about which session they are in
    return orchestrator_argv(key, batch_prompt({ ticket }, project_of(ticket.file, ticket.lnum)))
  end
  local dir = key and session_dir(key)
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
--- as a launch: it is the user's pane, quit by hand. A ticket in a project
--- orchestrator session resumes that session — the rules it runs under are the
--- orchestrator's, appended by `orchestrator_argv` when the session is opened
--- instead.
---@param ticket OrgTicket
---@return string[]
local function resume_argv(ticket)
  local key = session_key(ticket)
  if key and key:find '/' then
    -- a ticket in a project orchestrator session: the interactive instance to
    -- resume is the orchestrator, under the orchestrator's own rules
    return orchestrator_argv(key, nil)
  end
  local dir = key and session_dir(key)
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

--- The pane running the orchestrator of `key`, anywhere on the server.
---@param key string the orchestrator session key
---@return string|nil pane id
local function orchestrator_pane(key)
  local out = tmux { 'list-panes', '-a', '-F', '#{pane_id}\t#{@omp_orchestrator}' }
  if not out then
    return nil
  end
  for line in vim.gsplit(out, '\n', { plain = true }) do
    local pane, k = line:match '^(.-)\t(.*)$'
    if pane and k == key then
      return pane
    end
  end
end

--- Hand `message` to the omp running in `pane`: typed into its own prompt and
--- submitted, so the running instance takes it as its next message instead of
--- a second instance starting on the same tickets. `-l` sends the text
--- literally, and the message is one line, so no word of it is read as a key
--- name.
---@param pane string
---@param message string
---@return boolean
local function deliver(pane, message)
  local _, err = tmux { 'send-keys', '-t', pane, '-l', message }
  if err then
    notify('org ai: ' .. err, vim.log.levels.ERROR)
    return false
  end
  tmux { 'send-keys', '-t', pane, 'Enter' }
  return true
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

--- Open a pane running `argv` — a ticket's instance or a batch orchestrator:
--- the right-hand split of the nvim pane while that column is free, its own
--- tmux window inserted after the current one (`new-window -a`, the `prefix+n`
--- equivalent) once it is taken. Nothing here moves the active pane or window
--- (the split is created detached and respawned, the window with `-d`) and the
--- active pane returns to nvim at the end. The new pane carries `value` in its
--- `opt` pane option — what a later launch looks the instance up by. Returns
--- the pane id, or nil with a notification.
---@param argv string[]
---@param title string window / pane title
---@param opt string the pane option marking the instance
---@param value string
---@return string|nil pane
local function open_instance_pane(argv, title, opt, value)
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
    pane = tmux {
      'new-window',
      '-d',
      '-a',
      '-n',
      title,
      '-c',
      '#{pane_current_path}',
      '-P',
      '-F',
      '#{pane_id}',
      pane_command(argv),
    }
    if not pane then
      notify('org ai: could not open a tmux window', vim.log.levels.ERROR)
      return
    end
  else
    pane = split_for_run(cur)
    if not pane then
      notify('org ai: could not split the tmux window', vim.log.levels.ERROR)
      return
    end
    tmux { 'select-pane', '-t', pane, '-T', title }
    local _, err = tmux { 'respawn-pane', '-k', '-t', pane, pane_command(argv) }
    if err then
      notify('org ai: ' .. err, vim.log.levels.ERROR)
    end
  end
  tmux { 'set-option', '-p', '-t', pane, opt, value }
  -- what the run was asked and when it started: the little window that says
  -- what the runs are doing reads these off the pane (helpers/org/runs.lua),
  -- and every nvim in the session reads the same answer
  tmux { 'set-option', '-p', '-t', pane, '@omp_run_title', title }
  tmux { 'set-option', '-p', '-t', pane, '@omp_run_at', tostring(os.time()) }
  tmux { 'select-pane', '-t', cur }
  return pane
end

--- Hand `message` to the project's orchestrator: the instance with that
--- session key already running (`@omp_orchestrator`), or one opened for it --
--- the right-hand split while that column is free, its own window once it is
--- taken. Returns the pane and whether the message went to a running instance
--- rather than opening one; nil when nothing could be reached (the failure is
--- notified already).
---@param project OrgProject
---@param message string
---@return string|nil pane
---@return boolean delivered
local function start_orchestrator(project, message)
  local running = orchestrator_pane(project.key)
  if running then
    if not deliver(running, message) then
      return nil, false
    end
    return running, true
  end
  local pane = open_instance_pane(orchestrator_argv(project.key, message), '🤖 ' .. project.name, '@omp_orchestrator', project.key)
  return pane, false
end

--- Hand `message` to the talking instance: the one pane carrying `TALK_KEY`
--- in `@omp_orchestrator`, or a new one -- the right-hand split while that
--- column is free, its own window once it is taken. One instance, whatever
--- the renderer said and however many times: the same lookup a project's
--- orchestrator uses, keyed on the talking session instead, so the second
--- line of the day is typed into the conversation the first one started.
--- Returns the pane and whether the message went to the instance already
--- running rather than opening one; nil when nothing could be reached (the
--- failure is notified already).
---@param message string
---@return string|nil pane
---@return boolean delivered
local function open_talk(message)
  local running = orchestrator_pane(TALK_KEY)
  if running then
    if not deliver(running, message) then
      return nil, false
    end
    return running, true
  end
  local pane = open_instance_pane(talk_argv(message), '🤖 talk', '@omp_orchestrator', TALK_KEY)
  return pane, false
end

--- Start `ticket` for the headline and hand it to omp. Nothing here moves the
--- active pane or window: a ticket already running is reported instead of
--- focused, and its pane is opened detached.
---
--- A ticket the board links to a project orchestrator (a batch launched it, so
--- its :OMP_SESSION: is that session's key) is that instance's: handed over as
--- a batch of one when it runs, and opened under the orchestrator's own rules,
--- carrying `@omp_orchestrator` rather than a ticket's :ID:, when it does not
--- -- a second omp over the same session would be two agents on one history.
---@param ticket OrgTicket
local function open_pane(ticket)
  local key = session_key(ticket)
  if key and key:find '/' then
    local project = project_of(ticket.file, ticket.lnum)
    local _, delivered = start_orchestrator(project, batch_prompt({ ticket }, project))
    if delivered then
      notify('org ai: handed ' .. ticket.title .. ' to the running ' .. project.name .. ' orchestrator')
    end
    return
  end

  local running = running_pane(ticket.id)
  if running then
    notify('org ai: ' .. ticket.title .. ' is already running in pane ' .. running)
    return
  end
  open_instance_pane(omp_argv(ticket), '🤖 ' .. ticket.title, '@omp_ticket', ticket.id)
end

--- Start a batch of tickets on one omp: the project's orchestrator, whose
--- subagents do the working, so a frontier of `#tickets` costs one process
--- instead of one per ticket. A project whose orchestrator already runs is
--- handed the batch (`deliver`) rather than started a second time — an
--- orchestrator pane is looked up by its session key (`@omp_orchestrator`),
--- never by a ticket's :ID:, so no ticket's run can mistake it for its own
--- pane or close it.
---@param tickets OrgTicket[]
local function open_orchestrator(tickets)
  local project = project_of(tickets[1].file, tickets[1].lnum)
  local pane, delivered = start_orchestrator(project, batch_prompt(tickets, project))
  if not pane then
    return
  end
  if delivered then
    notify(('org ai: handed %d tickets to the running %s orchestrator'):format(#tickets, project.name))
  else
    notify(('org ai: %d tickets -> one %s orchestrator in pane %s'):format(#tickets, project.name, pane))
  end
end

--- Resume `ticket` with no pane of its own: open a tmux window running the
--- ticket's interactive omp session — inserted after the current one and
--- selected, so focus lands in it (what the jump is for). The pane carries the
--- ticket's :ID: in `@omp_ticket` — or, when the ticket's session is its
--- project's orchestrator, the session key in `@omp_orchestrator` — so the
--- next `<leader>aj` finds and focuses it instead of resuming again.
---@param ticket OrgTicket
local function resume_pane(ticket)
  local key = session_key(ticket)
  local orchestrator = key and key:find '/' ~= nil
  local project = orchestrator and project_of(ticket.file, ticket.lnum) or nil
  if project then
    project.key = key
  end
  local title = project and ('🤖 ' .. project.name) or ('🤖 ' .. ticket.title)
  local pane = tmux {
    'new-window',
    '-a',
    '-n',
    title,
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
  if orchestrator then
    tmux { 'set-option', '-p', '-t', pane, '@omp_orchestrator', key }
  elseif ticket.id and ticket.id:match '%S' then
    tmux { 'set-option', '-p', '-t', pane, '@omp_ticket', ticket.id }
  end
end

--- Without tmux, the run still resolves: a plain nvim terminal in a right
--- split, closed again once the omp process exits (same end state as the tmux
--- pane). No pane is tracked, so a second launch on the same ticket starts a
--- second instance — the tmux path is the predictable one.
---@param argv string[]
local function open_window(argv)
  vim.cmd 'belowright vert new'
  local win = vim.api.nvim_get_current_win()
  vim.fn.termopen(argv, {
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
  -- the tree changed on disk: the agenda's file list is cached for the burst
  -- of calls one render makes (helpers/org/agenda.lua) and has to be walked
  -- again -- a file added by another process is no write of a loaded buffer,
  -- so nothing else drops it
  require('helpers.org.agenda').drop_file_lists()
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

--- Launch every `target`: its own :ID: / :OMP_SESSION: / :OMP_LAUNCH: drawer, its claim
--- and its checkpoint. The buffers are launched in order and the lines within
--- one biggest first, so the property drawer the launcher writes on one entry
--- cannot shift the lines of a ticket still to come.
---
--- One target starts one omp instance of its own. Several start one *batch*:
--- a single orchestrator omp, its subagents working the tickets, because one
--- process per ticket is what a frontier of eighteen wanted from the machine.
--- The tickets still get everything the single launch gives them — the drawer,
--- the claim, the checkpoint — and their :OMP_SESSION: links each of them to
--- the batch's orchestrator session, so their jump and retro land there.
---
--- `claim` is handed to ticket_at: the caller has read the state of what it
--- launches and knows it was answered, so the launch stamps `NEXT` over it.
--- `origin` says who fired it, for the message the run opens with (the voice
--- card when the words, not a key, started it).
--- Returns how many tickets the launch found, and the tickets themselves.
---@param targets { bufnr: integer, lnum: integer }[]
---@param claim? boolean
---@param origin? string
---@return integer launched
---@return OrgTicket[]
local function launch_targets(targets, claim, origin)
  table.sort(targets, function(a, b)
    if a.bufnr == b.bufnr then
      return a.lnum > b.lnum
    end
    return a.bufnr < b.bufnr
  end)

  -- the batch is decided before a ticket is touched: the session each of them
  -- is linked to (the project's orchestrator) is part of the drawer write, and
  -- by the time the tickets are resolved their lines may already have moved
  local batch = #targets > 1 and project_of(vim.api.nvim_buf_get_name(targets[1].bufnr), targets[1].lnum) or nil

  local tickets = {}
  for _, target in ipairs(targets) do
    local ticket = ticket_at(target.bufnr, target.lnum, true, claim, batch and batch.key, origin)
    if ticket then
      checkpoint(ticket)
      tickets[#tickets + 1] = ticket
    end
  end

  if #tickets == 0 then
    return 0, tickets
  end
  if in_tmux() then
    if #tickets == 1 then
      open_pane(tickets[1])
    else
      open_orchestrator(tickets)
    end
  elseif #tickets == 1 then
    open_window(omp_argv(tickets[1]))
  else
    local project = project_of(tickets[1].file, tickets[1].lnum)
    open_window(orchestrator_argv(project.key, batch_prompt(tickets, project)))
  end
  return #tickets, tickets
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
--- the frontier below it (expand_target), the containers themselves untouched:
--- the one ticket is its own instance, several are one orchestrator
--- (`launch_targets`).
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
--- point -- its own :ID: / :OMP_SESSION: / :OMP_LAUNCH: drawer, its claim,
--- its checkpoint and its own omp pane. Unlike the mapping, the headline is
--- launched itself and never fanned out to the frontier below it: the caller
--- has already decided which headline, and the text it wrote (a note) sits on
--- that one.
---
--- This is what a note on a TEST entry triggers (helpers/org/notes.lua), and
--- there the state is a run's own: the note is the user's answer to the
--- hand-back, so the launch claims the entry back to `NEXT` (`claim`) instead
--- of leaving `TEST` standing, and the run that reads the note starts from a
--- ticket the board shows as taken.
---
--- The note itself reaches the run on its own: `ticket_at` reads the user's
--- newest turn out of the body (`user_turn`), so the message carries it --
--- here, and in a launch that never went through this function.
---@param bufnr integer
---@param lnum integer
function M.launch_at(bufnr, lnum)
  notify_launched(launch_targets({ { bufnr = bufnr, lnum = lnum } }, true))
  M.sync()
end

--- Hand a note to the run already working the ticket, when one is: the
--- ticket's own instance (`@omp_ticket` carries its :ID:) or the project
--- orchestrator that batch-launched it (`@omp_orchestrator` carries its
--- :OMP_SESSION: key). The note is typed into that instance's prompt, so the
--- run that is on the ticket reads it as its next message instead of a second
--- instance starting beside it on the same headline -- the note lands in the
--- entry body either way, which is the record.
---
--- Returns whether a run was on the ticket. A live run the note could not be
--- handed -- the buffer refusing the save an instance needs to read the note,
--- tmux refusing the keys -- still counts as `true`: the caller must not start
--- a second instance over a run that holds the ticket. The failure is
--- notified where it happens.
---@param bufnr integer
---@param lnum integer
---@param note string
---@return boolean live
function M.deliver_note(bufnr, lnum, note)
  if not in_tmux() then
    return false
  end
  local ticket = ticket_at(bufnr, lnum, false)
  if not (ticket and ticket.id) then
    return false
  end
  local key = session_key(ticket)
  local pane = (key and key:find '/') and orchestrator_pane(key) or running_pane(ticket.id)
  if not pane then
    return false
  end
  -- the running instance reads the note off the file, so the note has to be
  -- there before the message that points at it
  if not write.save(bufnr, { no_prompt = true }) then
    notify('org ai: ' .. vim.fn.fnamemodify(ticket.file, ':t') .. ' changed on disk — save or :e! before sending the note', vim.log.levels.WARN)
    return true
  end
  if deliver(pane, one_line(('Note on %s: %s'):format(ticket.title, note))) then
    notify('org ai: sent the note to the run on ' .. ticket.title)
  end
  return true
end

--- The words as a ticket: a headline in `target.file`, last under the entry
--- `target` names when it names one (a child headline, so the words hang off
--- what the user had highlighted), at the end of the file at the project
--- level when it names none. The body is the words under the capture header --
--- so the words sit on the board as a ticket the user can read before any run
--- touches it. The title is the words themselves, clipped at a word so the
--- headline stays one line.
---
--- `target` is `{ file, line?, id? }` -- what the page sent with the click, or
--- the spec the talking instance filed (`M.talk`) -- and it is resolved the way
--- every request from the page is (helpers/org/web/actions.lua): the :ID: wins,
--- the line is the fallback, and neither leaves the end of the file. nil when
--- it names no file the agenda reads.
---@param text string
---@param target { file: string, line?: integer, id?: string }
---@return { bufnr: integer, lnum: integer }|nil
local function preset_ticket(text, target)
  local ok, r = pcall(require('helpers.org.web.actions').resolve, target)
  if not (ok and r) then
    return nil
  end
  local hl = r.hl
  local file = require('org.files').get_buffer(r.bufnr)
  local lines = file.lines
  local level, at
  if hl then
    level = hl.level + 1
    at = math.min(hl.end_line or hl.line, #lines)
    while at > hl.line and (lines[at] or ''):match '^%s*$' do
      at = at - 1
    end
  else
    -- no entry named: the ticket joins the file's project at the end of it,
    -- one level under the project headline when the file has one
    local head = (file.headlines or {})[1]
    level = (head and head.level == 1) and 2 or 1
    at = #lines
    while at > 0 and (lines[at] or ''):match '^%s*$' do
      at = at - 1
    end
  end
  local title = text:gsub('%s+', ' ')
  if #title > 100 then
    title = vim.trim(title:sub(1, 100):gsub('%s+%S*$', '')) .. '…'
  end
  local out = {
    require('org.edit').build_headline { level = level, todo = 'TODO', title = title },
  }
  for _, line in ipairs(require('helpers.org.notes').block(hl, text)) do
    out[#out + 1] = '  ' .. line
  end
  if hl then
    vim.api.nvim_buf_set_lines(r.bufnr, at, at, false, out)
  else
    vim.api.nvim_buf_set_lines(r.bufnr, at, at, false, vim.list_extend({ '' }, out))
  end
  return { bufnr = r.bufnr, lnum = at + (hl and 1 or 2) }
end

--- Hand words that came from outside the board to the one talking instance
--- (`TALK_KEY`): the dashboard's voice card (helpers/org/voice.lua), and the
--- `:OrgVoice` / `:OrgVoiceSay` commands that speak the same way. Nothing is
--- filed here and no run starts here: the words go to the instance, and it is
--- what answers, files and starts a run (`M.talk`) -- one conversation for
--- every line the user says, whatever the view said them on.
---
--- The words ride along as a spec file, written beside the message: the words
--- themselves, the view they were said on, and -- when the dashboard had an
--- entry highlighted -- the file and the entry's :ID:, which is where the
--- ticket they become will hang. The instance reads the spec when it files
--- them (`M.talk`), so no quote of them has to survive a shell or a prompt.
---@param text string the words themselves
---@param target? { file: string, line?: integer, id?: string } what the
--- renderer had highlighted, when it had anything
---@param view? string the view they were said on
---@return string|nil pane the talking instance's pane ('' for a window of its
--- own, when this is not tmux), or nil when nothing could be reached
function M.open_prompt(text, target, view)
  local words = one_line(text)
  if words == '' then
    return nil
  end
  local spec = { text = words, view = view and view ~= '' and view or 'dashboard' }
  if target then
    spec.file = target.file
    spec.under = target.id
  end
  -- the words are written down where they outlive this nvim: the talking
  -- instance reads the spec when it files them, and the specs of a day are what
  -- the conversation was, so a temp file (gone when the editor exits) would be
  -- the wrong place for them
  local dir = vim.fs.dirname(session_dir(TALK_KEY)) .. '/specs'
  pcall(vim.fn.mkdir, dir, 'p')
  local path = ('%s/%d.json'):format(dir, vim.uv.hrtime())
  vim.fn.writefile({ vim.json.encode(spec) }, path)
  -- a spec is a few dozen bytes but every line of the day writes one: only the
  -- newest `SPECS_KEPT` stay, so the record is readable and the directory does
  -- not grow forever
  local kept = vim.fn.glob(dir .. '/*.json', true, true)
  if #kept > SPECS_KEPT then
    table.sort(kept, function(a, b)
      return vim.fn.fnamemodify(a, ':t') > vim.fn.fnamemodify(b, ':t')
    end)
    for i = SPECS_KEPT + 1, #kept do
      pcall(vim.fn.delete, kept[i])
    end
  end
  local msg =
    one_line(('Words said on the org %s view: "%s". Spec: %s. Answer them, or file the work and start it, as your rules say.'):format(spec.view, words, path))
  if not in_tmux() then
    open_window(talk_argv(msg))
    return ''
  end
  local pane, delivered = open_talk(msg)
  if not pane then
    return nil
  end
  notify(delivered and 'org ai: handed the words to the talking instance' or ('org ai: talking instance in pane ' .. pane))
  return pane
end

--- The talking instance's one act: the words in a spec file become a ticket,
--- and the ticket's run starts -- the write first, the run after, in that
--- order, so the board shows the work the moment the words are filed and the
--- dispatch is what takes the time.
---
--- Nothing is written by hand and nothing is invented here: the ticket is the
--- words (`preset_ticket`), and the launch is the ordinary one
--- (`launch_targets`: the :ID: / :OMP_SESSION: / :OMP_LAUNCH: drawer, the claim
--- to `NEXT`, the project checkpoint, a pane of its own) -- so a ticket spoken
--- into the renderer is indistinguishable on the board from one launched with
--- `<leader>ai`.
---
--- The spec carries the words, the file they belong to and the :ID: of the
--- entry they hang under (`M.open_prompt` writes it). `file` is the one thing
--- the talking instance may have to supply, as its second argument, when the
--- spec names none: a listen with nothing highlighted does not say which
--- project the words belong to, and the instance is what reads the vault.
---
--- This is called by the talking instance, from the shell of a headless nvim
--- (`nvim --headless -c "lua require('helpers.org.ai').talk('<spec>')" -c
--- 'qa!'`), so what it did is written to stdout as one line -- the instance
--- quotes it back to the user, and that line is the feedback the write exists
--- for.
---
--- The spec is marked with the `:ID:` it was filed as, so the same words are
--- one ticket however many times the instance runs the command: a second run
--- says which ticket they already are and writes nothing. One message is one
--- piece of work, and an agent that retried the command has not said it twice.
---@param spec_path string path of the spec JSON
---@param file? string the org file to file the words in, when the spec names none
---@return integer|nil lnum the headline's line, or nil when nothing was filed
function M.talk(spec_path, file)
  local say = function(msg)
    vim.api.nvim_out_write('org ai: ' .. msg .. '\n')
    notify('org ai: ' .. msg)
  end
  local raw = {}
  local ok_read, read = pcall(vim.fn.readfile, vim.fn.expand(spec_path))
  if ok_read then
    raw = read
  end
  local ok, spec = pcall(vim.json.decode, table.concat(raw, '\n'))
  if not (ok and type(spec) == 'table') then
    say('could not read the spec at ' .. spec_path)
    return nil
  end
  local words = one_line(spec.text or '')
  if words == '' then
    say('the spec at ' .. spec_path .. ' carries no words')
    return nil
  end
  if type(spec.filed) == 'string' and spec.filed ~= '' then
    say('already filed as :ID: ' .. spec.filed .. ' -- nothing written')
    return nil
  end
  local dest = (file and file ~= '') and file or spec.file
  if type(dest) ~= 'string' or dest == '' then
    say 'no org file for the words: pass one as the second argument'
    return nil
  end
  local under = type(spec.under) == 'string' and spec.under ~= '' and spec.under or nil
  local preset = preset_ticket(words, { file = vim.fn.expand(dest), id = under })
  if not preset then
    say('no org file at ' .. dest .. ' the agenda reads')
    return nil
  end
  local launched, tickets = launch_targets({ preset }, nil, 'the talking instance of the org renderer')
  M.sync()
  if launched == 0 or #tickets == 0 then
    say('could not start a run on "' .. words:sub(1, 60) .. '" (see the notification)')
    return nil
  end
  local ticket = tickets[1]
  spec.filed = ticket.id
  pcall(vim.fn.writefile, { vim.json.encode(spec) }, vim.fn.expand(spec_path))
  local pane = in_tmux() and running_pane(ticket.id) or nil
  say(('filed "%s" as :ID: %s in %s:%d'):format(ticket.title, ticket.id, ticket.file, ticket.lnum) .. (pane and (', run in pane ' .. pane) or ''))
  return preset.lnum
end

--- The climb up the tree, offered to every run at its end: the ordinary
--- launch applied to the ticket `id` hangs under, once this run closed the
--- last thing open below it. A leaf queued by launching its container is one
--- of a frontier (expand_target), and the tree only moves on once every leaf
--- of that frontier is closed -- so the duty is not split between them but
--- given to the last one to finish: each run offers the climb, and the one
--- that finds the level above it takeable takes it.
---
--- The climb is a launch, not one headline: it covers what `expand_headline`
--- reads off the file at that moment -- the parent itself when nothing is
--- open below it, and the tickets left open and takeable under the parent
--- otherwise (a sibling this run did not close, a ticket charted into that
--- subtree since the level was last launched) -- so a level that rises with
--- several tickets takeable at once starts all of them, exactly as launching
--- the parent would. What no run has touched is what it starts: the tickets
--- are narrowed to `TODO`, so a sibling a run already
--- claimed (`NEXT`), one awaiting the user's validation (`TEST`), one parked
--- on the user (`PEND`) or one that failed (`WARN`) is left alone -- that
--- keeps the duty on the last leaf to finish, which is the only run whose
--- climb finds untouched work left to start. The level above itself is the one
--- exception, and only at `NEXT` (RISING): a claim on a headline that holds
--- open work below it is impossible -- a launch fans out to that work and
--- leaves the container unstamped -- so a `NEXT` there is the level's own
--- marker while the work under it runs, the map of an expedition above all,
--- and the climb rising onto it is what launches the map pass that closes the
--- expedition. A run still on it is refused by the launch itself
--- (`open_pane`), so nothing double-starts. The launch is the ordinary one
--- -- :ID: / :OMP_SESSION: / :OMP_LAUNCH:, the claim, the project checkpoint,
--- its own pane -- so a level that is one ticket opens one instance and a
--- level of several is one orchestrator batch (`launch_targets`). A ticket
--- whose parent is no ticket (the project's own headline, a grouping line) has
--- nowhere to climb to and says so.
---
--- This is the run's own entry point, called from the shell of an
--- omp-org-ticket run as its last act before the pane goes (the skill), with
--- the ticket's :ID: and file -- the pair the launch message already gives
--- it:
---
---   nvim --headless -u <init.lua> -c "lua require('helpers.org.ai').climb_up('<file>', '<id>')" -c 'qa!'
---
--- Its answer is written to stdout for that shell (the notify a run would
--- otherwise read is not what a headless instance leaves behind).
---@param file string the ticket's org file
---@param id string the ticket's :ID:
function M.climb_up(file, id)
  local say = function(msg)
    vim.api.nvim_out_write('org ai: ' .. msg .. '\n')
    notify('org ai: ' .. msg)
  end
  local buf = vim.fn.bufadd(vim.fs.normalize(file))
  vim.fn.bufload(buf)
  local parsed = require('org.files').get_buffer(buf)
  local hl
  for _, h in ipairs((parsed and parsed.headlines) or {}) do
    if h.properties.ID == id then
      hl = h
      break
    end
  end
  if not hl then
    say('no headline carries :ID: ' .. id .. ' in ' .. file)
    return
  end
  local parent = hl.parent
  if not (parent and parent:is_todo()) then
    say('nothing above ' .. hl:plain_title() .. ' to climb to')
    return
  end

  -- the level above, as a launch on the parent would cover it, narrowed to
  -- what this run may start: the tickets no run has touched (UNTOUCHED -- a
  -- `PEND` or a `TEST` the level above holds is waiting on the user, not on
  -- this run) -- the parent when it is free, the untouched tickets left
  -- takeable below it otherwise -- and the parent itself when it reads `NEXT`
  -- and holds nothing open below it (RISING: the level rising, not a ticket a
  -- run is on -- see its own note)
  local targets, titles = {}, {}
  for _, cand in ipairs(expand_headline(parent)) do
    local rising = cand == parent -- nothing under it is open: the level itself
    if UNTOUCHED[cand.todo] or (rising and RISING[cand.todo]) then
      targets[#targets + 1] = { bufnr = buf, lnum = cand.line }
      titles[#titles + 1] = cand:plain_title()
    end
  end

  if #targets == 0 then
    if parent:has_undone_children() then
      say(parent:plain_title() .. ' has no untouched ticket left below it; the one that closed made the climb')
    else
      say(parent:plain_title() .. ' is not takeable (' .. (parent.todo or 'no keyword') .. ')')
    end
    return
  end

  local launched = launch_targets(targets)
  local list = table.concat(titles, ', ')
  if launched == 0 then
    say('could not launch ' .. list .. ' (see the notification)')
  elseif launched == 1 then
    say('climbed to ' .. list)
  else
    say(('climbed to %d tickets at or under %s: %s'):format(launched, parent:plain_title(), list))
  end
end

--- `<leader>ai` over a Visual selection: the Visual-mode shape of M.launch.
--- Every entry the selection covers is launched exactly as it would be on
--- its own — its own :ID: / :OMP_SESSION: / :OMP_LAUNCH: drawer, its claim, its
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
--- focused. A ticket launched in a batch is the project orchestrator's: the
--- jump lands on that instance (its pane carries the session key, not a
--- ticket's :ID:), never on a second omp over the same session. The headline
--- itself is never written to.
function M.jump()
  if not in_tmux() then
    notify('org ai: not in tmux', vim.log.levels.WARN)
    return
  end
  local ticket = ticket_at_cursor(false)
  if not ticket then
    return
  end
  local key = session_key(ticket)
  if key and key:find '/' then
    local pane = orchestrator_pane(key)
    if pane then
      focus_pane(pane)
      return
    end
    resume_pane(ticket)
    return
  end
  if ticket.id and ticket.id:match '%S' then
    local pane = running_pane(ticket.id)
    if pane then
      focus_pane(pane)
      return
    end
  end
  if not key then
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
