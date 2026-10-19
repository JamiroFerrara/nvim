-- `OrgRetro` (and `<leader>ar` in the TODO view or an org buffer): one omp run
-- over the agent sessions of every finished ticket.
--
-- The ticket -> session link is helpers/org/ai.lua's: a launch stamps the
-- headline with `:OMP_SESSION:` (the key of the ticket's session directory
-- under the omp agent directory, `tickets/<key>`), so a finished ticket still
-- points at the whole history of the agent that worked it. `OrgRetro` walks
-- the agenda files, takes every DONE headline that carries the property and
-- holds at least one session file, and starts a single omp instance over all
-- of them with the `retro` skill appended: one retrospective of the agent
-- workflow, fed by every ticket at once instead of one session at a time.
--
-- The run goes to a detached tmux window running `nvim "+terminal omp …"` --
-- the pane shape helpers/org/ai.lua gives a ticket, so Terminal-Normal vim
-- keys and the tmux `is_vim` pane moves work here too -- or to a plain
-- terminal split without tmux. The report lands in a dated file under
-- ~/org/roam/retro/, and the notification names it.
--
-- `OrgKb` (`<leader>oK`) is the same machinery over the *current board* with
-- the `kb` skill appended instead: it consolidates what the project's tickets
-- taught into ~/org/roam/documentation/ and rebuilds the hub. A ticket run
-- cannot do this -- helpers/org/ai.lua's contract is one headline, and
-- consolidation spans a whole project, its board and its archive.
local M = {}

local SKILL = vim.fn.expand '~/.agents/skills/retro/SKILL.md'
-- The knowledge-base skill, appended instead by `OrgKb` (`M.consolidate`).
local KB_SKILL = vim.fn.expand '~/.agents/skills/kb/SKILL.md'
-- The property helpers/org/ai.lua writes on a launched ticket.
local SESSION_PROP = 'OMP_SESSION'
-- Reports land in ~/org/roam/retro/ -- inside the knowledge base, beside the
-- material they reflect on, and in the ~/org repo (git history is the point of
-- a retrospective). They are `.md`, so the roam index leaves them alone: they
-- are the record of how the system evolved, not knowledge about a project.
local REPORT_DIR = vim.fn.expand '~/org/roam/retro'

local function notify(msg, level)
  require('org.utils').notify(msg, level)
end

--- omp's agent directory: `PI_CODING_AGENT_DIR` when set, else omp's default
--- (`~/.omp/agent`). Where helpers/org/ai.lua keeps a ticket's session dir.
---@return string
local function agent_dir()
  local dir = vim.env.PI_CODING_AGENT_DIR
  if dir and dir ~= '' then
    return vim.fs.normalize(dir)
  end
  return vim.fn.expand '~/.omp/agent'
end

--- The session files of the ticket linked by `key` (its :OMP_SESSION:).
---@param key string
---@return string[]
local function session_files(key)
  return vim.fn.glob(agent_dir() .. '/tickets/' .. key .. '/*.jsonl', false, true)
end

--- Every DONE ticket of the agenda files that has run an agent, as
--- { file, title, sessions }.
---@return table[]
local function finished()
  local files = require 'org.files'
  local out = {}
  for _, path in ipairs(files.agenda_file_paths()) do
    local file = files.get(path)
    for _, hl in ipairs(file and file.headlines or {}) do
      local key = hl:get_property(SESSION_PROP, false)
      key = key and vim.trim(key)
      if key and key ~= '' and hl:is_done() then
        local sessions = session_files(key)
        if #sessions > 0 then
          out[#out + 1] = { file = path, title = hl:plain_title(), sessions = sessions }
        end
      end
    end
  end
  return out
end

--- The report file of this run: one dated file under the nvim data directory,
--- so a day's retros collect in one place.
---@return string
local function report_path()
  vim.fn.mkdir(REPORT_DIR, 'p')
  return REPORT_DIR .. '/' .. os.date '%Y-%m-%d' .. '.md'
end

--- The message the retro omp starts with: every ticket and its session logs,
--- and where to write the report. One line, like helpers/org/ai.lua's ticket
--- prompt: the pane runs it through `nvim "+terminal …"`, and nvim executes
--- the whole `+{cmd}` as Ex commands, so a newline splits the prompt into a
--- second (invalid) Ex command (`E492`) instead of reaching omp.
---@param tickets table[]
---@param report string
---@return string
local function prompt(tickets, report)
  local parts = {
    string.format('Retrospective requested from nvim over %d finished org ticket(s) and the agent sessions they ran.', #tickets),
    'The retro skill is appended to your system prompt: follow it.',
    'Read the session logs below -- they are the primary sources -- and report the changes to the agent environment (navigation, automated checks, coding standards, tool economy) ordered by severity.',
    'Compare the sessions: a pattern that repeats across tickets matters more than what any one session did.',
    'Write the report to ' .. report .. ' with the write tool; that file is the deliverable, and your final message is one line saying where it landed.',
    'Tickets:',
  }
  for _, t in ipairs(tickets) do
    parts[#parts + 1] = '- ' .. t.title .. ' (' .. t.file .. '): ' .. table.concat(t.sessions, ', ')
  end
  return table.concat(parts, ' ')
end

--- The pane command running `argv`: `nvim "+terminal omp …"`, the same shape
--- helpers/org/ai.lua gives a ticket (Terminal-Normal vim keys, tmux `is_vim`
--- pane moves). The whole `+terminal …` is one shell word, so each layer is
--- quoted for the shell that reads it.
---@param argv string[]
---@return string
local function pane_command(argv)
  local omp = table.concat(vim.tbl_map(vim.fn.shellescape, argv), ' ')
  return table.concat(vim.tbl_map(vim.fn.shellescape, { 'nvim', '+terminal ' .. omp }), ' ')
end

--- Start `argv` in a detached tmux window (the current window stays selected,
--- so nvim keeps focus), or in a plain terminal split without tmux.
---@param argv string[]
local function spawn(argv)
  if vim.env.TMUX and vim.env.TMUX ~= '' then
    local out = vim.fn.system {
      'tmux',
      'new-window',
      '-d',
      '-a',
      '-n',
      '🤖 omp',
      '-c',
      '#{pane_current_path}',
      '-P',
      '-F',
      '#{pane_id}',
      pane_command(argv),
    }
    if vim.v.shell_error ~= 0 then
      notify('org retro: tmux: ' .. vim.trim(out), vim.log.levels.ERROR)
    end
    return
  end
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

--- `OrgRetro`: one retrospective over the sessions of every finished ticket.
function M.run()
  local tickets = finished()
  if #tickets == 0 then
    notify('org retro: no finished ticket has run an agent yet', vim.log.levels.WARN)
    return
  end
  local report = report_path()
  local total = 0
  for _, t in ipairs(tickets) do
    total = total + #t.sessions
  end
  spawn { 'omp', '--append-system-prompt', SKILL, prompt(tickets, report) }
  notify(string.format('org retro: %d ticket(s), %d session(s) → %s', #tickets, total, report))
end

--- The board the consolidation runs over: the org file in the current window
--- when it is a board, else the project resolved from the cwd (the same
--- resolution `°`, `^` and `£` use, so it works from the TODO view too).
---@return string|nil
local function board()
  local path = vim.api.nvim_buf_get_name(0)
  if vim.bo.filetype == 'org' and path:match '/org/projects/[^/]+%.org$' then
    return path
  end
  local project = require('helpers.org.project').current()
  return project and project.file or nil
end

--- The message a consolidation omp starts with (one line: see `prompt`).
---@param board_path string
---@return string
local function kb_prompt(board_path)
  local client = vim.fn.fnamemodify(board_path, ':t:r')
  return table.concat({
    'Knowledge-base consolidation requested from nvim for ' .. client .. '.',
    'The kb skill is appended to your system prompt: follow its "Consolidating" section.',
    'Board: ' .. board_path .. ' -- the tickets of this project, open and closed.',
    'Knowledge base: ' .. vim.fn.expand('~/org/roam/documentation/' .. client .. '.org')
      .. ' (create it from the board\'s level-1 headings if it is not there yet).',
    'The closed tickets are in ' .. vim.fn.expand('~/org/archive/' .. client .. '/*.org_archive')
      .. ' and, for the ones rolled before that, in ' .. vim.fn.expand('~/org/projects/' .. client .. '.org_archive') .. '.',
    'The scope is the whole project, not one headline: the single-ticket rule of the omp-org-ticket contract does not apply to this run.',
    'Rebuild the hub when you are done: nvim --headless -c \'lua require("helpers.org.kb").index()\' -c \'qa!\'.',
    'Your final message is one line: what merged, what you added, what is still a draft.',
  }, ' ')
end

--- `OrgKb` (`<leader>oK`): consolidate the board's tickets into the knowledge
--- base, one omp run with the `kb` skill appended.
function M.consolidate()
  local path = board()
  if not path or path == '' then
    notify('org kb: no board here, and the cwd names no project', vim.log.levels.WARN)
    return
  end
  if vim.fn.filereadable(KB_SKILL) == 0 then
    notify('org kb: ' .. KB_SKILL .. ' is missing', vim.log.levels.ERROR)
    return
  end
  spawn { 'omp', '--append-system-prompt', KB_SKILL, kb_prompt(path) }
  notify('org kb: consolidating ' .. vim.fn.fnamemodify(path, ':t') .. ' into ' .. vim.fn.expand '~/org/roam/documentation/')
end

function M.setup()
  vim.api.nvim_create_user_command('OrgRetro', M.run, {
    desc = 'Retrospective over the agent sessions of the finished org tickets',
  })
  vim.api.nvim_create_user_command('OrgKb', M.consolidate, {
    desc = 'Consolidate the board’s tickets into the knowledge base',
  })
  -- `<leader>ar` shadows the global readability key in org buffers and the
  -- TODO view, like `<leader>ai` shadows the plain-omp terminal key there;
  -- both are meaningless on org prose. `<leader>oK` and the hub's
  -- `<leader>omh` are org-only for the same reason.
  vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'org', 'orgagenda' },
    callback = function(args)
      vim.keymap.set('n', '<leader>ar', M.run, {
        buffer = args.buf,
        desc = 'org: retro over the finished tickets',
      })
      vim.keymap.set('n', '<leader>oK', M.consolidate, {
        buffer = args.buf,
        desc = 'org: consolidate the board into the knowledge base',
      })
      vim.keymap.set('n', '<leader>omh', function()
        require('helpers.org.kb').index()
      end, {
        buffer = args.buf,
        desc = 'org: rebuild the knowledge-base hub',
      })
      vim.keymap.set('n', '<leader>omq', function()
        require('helpers.org.kb').query(vim.fn.input 'kb query: ')
      end, {
        buffer = args.buf,
        desc = 'org: query the knowledge base',
      })
    end,
  })
end

return M
