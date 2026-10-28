-- Write side of the browser views (helpers/org/web/init.lua): the dashboard
-- changes an entry's TODO keyword and opens its file, and both go through
-- org.nvim's own commands, so the CLOSED stamp, the logging drawer, the
-- parent statistics and the state-change hooks behave as they do in the
-- editor.
--
-- A request names the entry by file and line, the line it was rendered at.
-- Between the render and the click the file may have moved under the entry
-- (`D` in the TUI, an agent's write-back), so the `:ID:` wins when the entry
-- has one, and the line is only a fallback for the entries that carry none.
local M = {}

--- Restrict a request path to the files the agenda reads.
---@param path string
---@return string|nil
local function agenda_path(path)
  if type(path) ~= 'string' or path == '' then
    return nil
  end
  local abs = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
  for _, known in ipairs(require('org.files').agenda_file_paths()) do
    if known == abs then
      return abs
    end
  end
  return nil
end

M.agenda_path = agenda_path

--- The buffer of `path`, loaded, and its text brought up to date with the
--- file when the buffer holds no edits of its own (an agent's write-back,
--- another editor). helpers/org/write.lua's refresh swaps the lines in
--- place and records the read, so the save after an edit can be forced
--- instead of asking a question nobody on this side of the request can
--- answer.
---@param path string
---@return integer
local function buffer_for(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(path)
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end
  pcall(function()
    require('helpers.org.write').refresh(bufnr)
  end)
  return bufnr
end

--- The headline a request means: by `:ID:` when it has one, else the
--- headline owning `line`.
---@param bufnr integer
---@param line integer|nil
---@param id string|nil
---@return org.Headline|nil
local function headline_at(bufnr, line, id)
  local file = require('org.files').get_buffer(bufnr)
  if not file then
    return nil
  end
  if id and id ~= '' then
    local found = file:find_by_id(id)
    if found then
      return found
    end
  end
  if not line then
    return nil
  end
  return file:headline_at(line)
end

--- The file, buffer and headline a request names.
---@param spec { file: string, line?: integer, id?: string }
---@return { path: string, bufnr: integer, hl: org.Headline|nil }|nil
function M.resolve(spec)
  local path = agenda_path(spec and spec.file)
  if not path then
    return nil
  end
  local bufnr = buffer_for(path)
  return { path = path, bufnr = bufnr, hl = headline_at(bufnr, tonumber(spec.line), spec.id) }
end

local resolve = M.resolve

--- Write the edit back the way the view does, then drop the payload cache so
--- the next page load walks the files again. Returns the save's verdict and
--- its reason, which the page shows as a warning.
---@param bufnr integer
---@return boolean saved, string|nil error
function M.commit(bufnr)
  local saved, err = require('helpers.org.write').save(bufnr, { no_prompt = true })
  require('helpers.org.web.data').invalidate()
  return saved, (not saved) and err or nil
end

local commit = M.commit

--- The keyword of one headline becomes `state` ('' clears it), the way the
--- editor's own state change does, and the file is written. The caller has
--- already resolved the buffer and the headline.
---@param bufnr integer
---@param hl org.Headline
---@param state string
---@return string|nil state, string|nil error, string|nil warning
local function change_state(bufnr, hl, state)
  local ok, result = pcall(require('org.todo').change_state, { bufnr = bufnr, lnum = hl.line }, state or '')
  if not ok then
    return nil, tostring(result)
  end
  if not result then
    return nil, 'state change blocked'
  end
  -- no_prompt: a request cannot answer the W12 question, so a write the
  -- module cannot prove safe is refused and reported instead of hanging
  local saved, save_err = commit(bufnr)
  return result.new or '', nil, (not saved) and save_err or nil
end

--- Set the TODO keyword of one entry. Returns the state it now reads, the
--- reason when nothing changed, and a warning when the change landed in the
--- buffer but could not be written (the editor's own conflict to resolve).
---@param spec { file: string, line?: integer, id?: string }
---@param state string
---@return string|nil state, string|nil error, string|nil warning
function M.set_state(spec, state)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  return change_state(r.bufnr, r.hl, state)
end

--- Show one entry in a window of this nvim.
---@param spec { file: string, line?: integer, id?: string }
---@return boolean
function M.open(spec)
  local path = agenda_path(spec and spec.file)
  if not path then
    return false
  end
  local bufnr = buffer_for(path)
  local hl = headline_at(bufnr, tonumber(spec.line), spec.id)
  vim.api.nvim_set_current_buf(bufnr)
  if hl then
    pcall(vim.api.nvim_win_set_cursor, 0, { hl.line, 0 })
    vim.cmd 'normal! zv'
  end
  return true
end

--- The entry's own lines -- headline through the end of its subtree -- for
--- the browser's editor. `start` is where they sit in the file, so the page
--- can show the line and the write can say what it replaced.
---@param spec { file: string, line?: integer, id?: string }
---@return { start: integer, lines: string[], level: integer, path: string }|nil text, string|nil error
function M.text(spec)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local lines = vim.api.nvim_buf_get_lines(r.bufnr, r.hl.line - 1, r.hl.end_line, false)
  return { start = r.hl.line, lines = lines, level = r.hl.level, path = r.path }, nil
end

--- Replace the entry's lines with `lines` and save. The range is resolved
--- again here (by `:ID:` when the entry has one), so a file that moved under
--- the open editor still takes the edit at the entry it was written for.
---@param spec { file: string, line?: integer, id?: string }
---@param lines string[]
---@return { ok: boolean, lines: string[], start: integer }|nil out, string|nil error
function M.write(spec, lines)
  if type(lines) ~= 'table' or #lines == 0 then
    return nil, 'no text'
  end
  local clean = {}
  for i, line in ipairs(lines) do
    if type(line) ~= 'string' then
      return nil, 'bad line ' .. i
    end
    clean[i] = (line:gsub('\r', ''))
  end
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local ok, err = pcall(vim.api.nvim_buf_set_lines, r.bufnr, r.hl.line - 1, r.hl.end_line, false, clean)
  if not ok then
    return nil, tostring(err)
  end
  local saved, save_err = commit(r.bufnr)
  return { ok = saved and true or false, start = r.hl.line, lines = clean }, save_err
end

--- `N` in the view: the entry's keyword moves on one step.
---@param spec { file: string, line?: integer, id?: string }
---@return table|nil out, string|nil error
function M.cycle(spec)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local ok, res = pcall(require('org.todo').cycle_next, { bufnr = r.bufnr, lnum = r.hl.line })
  if not ok then
    return nil, tostring(res)
  end
  if not res then
    return nil, 'state change blocked'
  end
  local _, err = commit(r.bufnr)
  return { state = res.new or '', old = res.old or '' }, err
end

--- `B`/`F`/`C` (one tag) or `t` (the whole set): the entry's tags become
--- `tags`, and a bare toggle arrives as the one-tag form.
---@param spec { file: string, line?: integer, id?: string }
---@param tags string[]|string
---@return { tags: string[] }|nil out, string|nil error
function M.tags(spec, tags)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local ok, err
  if type(tags) == 'string' then
    ok, err = pcall(require('org.tags').toggle_tag, { bufnr = r.bufnr, lnum = r.hl.line }, tags)
  else
    local list = {}
    for _, tag in ipairs(tags or {}) do
      if type(tag) == 'string' and tag ~= '' then
        list[#list + 1] = tag
      end
    end
    ok, err = pcall(require('org.tags').set_tags, { bufnr = r.bufnr, lnum = r.hl.line }, list, true)
  end
  if not ok then
    return nil, tostring(err)
  end
  local _, save_err = commit(r.bufnr)
  local now = headline_at(r.bufnr, r.hl.line, spec.id)
  return { tags = now and now.tags or {} }, save_err
end

--- `p`: the entry's priority becomes `value` ('' clears it).
---@param spec { file: string, line?: integer, id?: string }
---@param value string
---@return { priority: string|nil }|nil out, string|nil error
function M.priority(spec, value)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local ok, err = pcall(require('org.priority').set, { bufnr = r.bufnr, lnum = r.hl.line }, value and value ~= '' and value or ' ')
  if not ok then
    return nil, tostring(err)
  end
  local _, save_err = commit(r.bufnr)
  return { priority = (value ~= '' and value or nil) }, save_err
end

--- `a`: archive the entry's subtree, the way the view's archive action does.
---@param spec { file: string, line?: integer, id?: string }
---@return { ok: boolean }|nil out, string|nil error
function M.archive(spec)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local ok, err = pcall(require('org.archive').archive_subtree_default, { bufnr = r.bufnr, lnum = r.hl.line })
  if not ok then
    return nil, tostring(err)
  end
  local _, save_err = commit(r.bufnr)
  return { ok = true }, save_err
end

--- `dd`: delete the entry's whole subtree, like the view's kill action.
---@param spec { file: string, line?: integer, id?: string }
---@return { ok: boolean }|nil out, string|nil error
function M.kill(spec)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local last = r.hl.end_line
  -- the blank line the subtree leaves behind goes with it
  local total = vim.api.nvim_buf_line_count(r.bufnr)
  if last < total and (vim.api.nvim_buf_get_lines(r.bufnr, last, last + 1, false)[1] or '') == '' then
    last = last + 1
  end
  local ok, err = pcall(vim.api.nvim_buf_set_lines, r.bufnr, r.hl.line - 1, last, false, {})
  if not ok then
    return nil, tostring(err)
  end
  local _, save_err = commit(r.bufnr)
  return { ok = true }, save_err
end

--- `u`: undo the last change made to the entry's file -- the view actions
--- all write through the buffer, so nvim's own undo is the view's undo.
---@param spec { file: string, line?: integer, id?: string }
---@return { ok: boolean }|nil out, string|nil error
function M.undo(spec)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  local before = vim.api.nvim_buf_get_changedtick(r.bufnr)
  local ok, err = pcall(function()
    vim.api.nvim_buf_call(r.bufnr, function()
      vim.cmd 'silent! undo'
    end)
  end)
  if not ok then
    return nil, tostring(err)
  end
  if vim.api.nvim_buf_get_changedtick(r.bufnr) == before then
    return nil, 'nothing to undo'
  end
  local saved, save_err = commit(r.bufnr)
  return { ok = saved and true or false }, save_err
end

--- `r`: refile the entry's subtree under another headline (`dest`).
---@param spec { file: string, line?: integer, id?: string }
---@param dest { file: string, line?: integer, id?: string }
---@return { ok: boolean }|nil out, string|nil error
function M.refile(spec, dest)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local d = resolve(dest)
  if not (d and d.hl) then
    return nil, 'no destination'
  end
  if d.bufnr == r.bufnr and d.hl.line >= r.hl.line and d.hl.line <= r.hl.end_line then
    return nil, 'cannot refile into its own subtree'
  end
  local ok, err = pcall(require('org.refile').refile, { bufnr = r.bufnr, lnum = r.hl.line }, {
    dest = { bufnr = d.bufnr, lnum = d.hl.line },
  })
  if not ok then
    return nil, tostring(err)
  end
  local saved, save_err = commit(r.bufnr)
  if d.bufnr ~= r.bufnr then
    require('helpers.org.write').save(d.bufnr, { no_prompt = true })
  end
  return { ok = saved and true or false }, save_err
end

--- `<Space>ai` / `<Space>aj`: hand the entry to the launcher, which starts an
--- `omp` run on it in a tmux pane (or jumps to the one already running).
--- Both run out of the request's own callback, so a launch that writes and
--- commits does not hold the answer to the page.
---@param spec { file: string, line?: integer, id?: string }
---@param jump boolean
---@return { ok: boolean }|nil out, string|nil error
function M.launch(spec, jump)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local bufnr, lnum = r.bufnr, r.hl.line
  vim.schedule(function()
    local ai = require 'helpers.org.ai'
    if jump then
      vim.api.nvim_set_current_buf(bufnr)
      pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
      pcall(ai.jump)
    else
      pcall(ai.launch_at, bufnr, lnum)
    end
  end)
  return { ok = true }, nil
end

--- The date header of a captured entry or a note: `[<timestamp>] <rule>`
--- (helpers/org/notes.lua's `entry_lines`), taken at the moment the request
--- runs.
---@return string
local function header()
  local date = require 'org.date'
  local ts = date.effective_now(nil):clone({ active = false }):to_string()
  return ts .. ' ' .. string.rep('-', require('helpers.org.notes').DASHES)
end

--- The description typed under a captured entry's title, as the lines that
--- follow its header: one per line, indented like the template's own `  `,
--- blank lines left empty. Leading and trailing blank lines are dropped, the
--- way org.nvim trims a stored capture.
---@param body string|nil
---@return string[]
local function description(body)
  local out = {}
  if type(body) ~= 'string' then
    return out
  end
  for _, line in ipairs(vim.split((body:gsub('\r', '')), '\n', { plain = true })) do
    line = (line:gsub('%s+$', ''))
    out[#out + 1] = line
  end
  while out[1] and out[1] == '' do
    table.remove(out, 1)
  end
  while out[#out] and out[#out] == '' do
    out[#out] = nil
  end
  return out
end

--- Capture a new task from the browser form: the entry the editor's `^` /
--- `<leader>oc` capture writes. The config's Task template (the same one,
--- `capture.templates.t` of lua/terminal_plugins/org.nvim.lua) gives the
--- shape -- a `TODO` title, the date header under it, the description below
--- -- and the two store filters of helpers/org/capture.lua and
--- helpers/org/autotags.lua add the tags: the destination's own and
--- inherited set, and the words the title and description carry. org.nvim's
--- own capture placement (`org.capture.insert`) then puts the lines at the
--- end of the target's subtree, so the parent's `[n/m]` cookie counts the new
--- entry and the nesting is the one the destination implies.
---
--- The request names the entry to capture under by `:ID:` or line -- the
--- `c` / `<leader>aC` capture-under-entry, from the detail pane. With
--- neither, the entry goes under the file's first level-1 headline, where a
--- project capture lands when the cwd named the project
--- (helpers/org/capture.lua's `pick`). No `%a` link back to an origin is
--- written: the browser is not a file (helpers/org/capture.lua's
--- `origin_link`).
---@param spec { file: string, line?: integer, id?: string, title: string, body?: string }
---@return { line: integer, title: string }|nil out, string|nil error
function M.capture(spec)
  local raw = spec and spec.title
  local title = type(raw) == 'string' and vim.trim((raw:gsub('[\r\n]+', ' '))) or ''
  if title == '' then
    return nil, 'a capture needs a title'
  end
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  local file = require('org.files').get_buffer(r.bufnr)
  local parent = r.hl or (file and file.children and file.children[1])
  if not parent then
    return nil, 'no headline to capture under'
  end
  local olp = parent:outline_path()
  olp[#olp + 1] = parent:plain_title()
  local tpl = { key = 't', type = 'entry', target = r.path, olp = olp }
  local ctx = { target_file = file, target_hl = parent, noninteractive = true, date = require('org.date').now() }
  local lines = { '* TODO ' .. title, '  ' .. header() }
  for _, line in ipairs(description(spec.body)) do
    lines[#lines + 1] = line == '' and '' or '  ' .. line
  end
  local capture = require 'helpers.org.capture'
  lines = capture.header_first(tpl, lines) or lines
  lines = capture.capture_tags(tpl, lines, ctx) or lines
  lines = require('helpers.org.autotags').filter(tpl, lines, ctx) or lines
  local ok, first = pcall(require('org.capture').insert, r.bufnr, tpl, lines, ctx)
  if not ok then
    return nil, tostring(first)
  end
  if not first then
    return nil, 'capture target is gone'
  end
  local saved, err = commit(r.bufnr)
  return { line = first, title = title }, (not saved) and err or nil
end

--- Add a timestamped note to the end of an entry's body -- the
--- `<leader>n` / `z` note of the editor, whose block shape
--- helpers/org/notes.lua owns -- and save it. A note on an entry in `TEST`
--- is the user's answer to the run that handed it back, so it also launches
--- the ticket, exactly as the editor's note does; the launch is deferred to
--- the next event-loop turn, so the page gets its answer and the launch's
--- own writes land after the note is saved.
---@param spec { file: string, line?: integer, id?: string }
---@param text string|nil
---@return { line: integer, launched: boolean }|nil out, string|nil error
function M.note(spec, text)
  local r = resolve(spec)
  if not r then
    return nil, 'unknown file'
  end
  if not r.hl then
    return nil, 'entry not found'
  end
  local retest = r.hl.todo == 'TEST'
  local first = require('helpers.org.notes').store(r.bufnr, r.hl, text)
  if not first then
    return nil, 'the note is empty'
  end
  local saved, err = commit(r.bufnr)
  if retest then
    local bufnr, lnum = r.bufnr, r.hl.line
    vim.schedule(function()
      pcall(require('helpers.org.ai').launch_at, bufnr, lnum)
    end)
  end
  return { line = first, launched = retest }, (not saved) and err or nil
end

--- The entry's subtree as exported HTML, for the dashboard's detail pane.
---@param spec { file: string, line?: integer, id?: string }
---@return string|nil html, string|nil error
function M.entry_html(spec)
  local path = agenda_path(spec and spec.file)
  if not path then
    return nil, 'unknown file'
  end
  local bufnr = buffer_for(path)
  local wanted = tonumber(spec.line) or spec.id
  local hl = wanted and headline_at(bufnr, tonumber(spec.line), spec.id) or nil
  if wanted and not hl then
    return nil, 'entry not found'
  end
  -- no headline asked for (the cursor above the first one): the whole file
  local ok, html = pcall(function()
    return require('org.export').to_string('html', {
      bufnr = bufnr,
      subtree_line = hl and hl.line or nil,
      body_only = true,
    })
  end)
  if not ok then
    return nil, tostring(html)
  end
  -- the exporter colours source blocks with Emacs' htmlize, writes a turn's
  -- header as raw text and a headline as one flat run; the browser shows the
  -- blocks the way the buffer does (helpers/org/web/highlight), the header as
  -- the date it carries (helpers/org/web/turns) and the headline's parts on
  -- one line (helpers/org/web/headings)
  html = require('helpers.org.web.highlight').html(html)
  html = require('helpers.org.web.turns').headers(html)
  return require('helpers.org.web.headings').html(html), nil
end

return M
