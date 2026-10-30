-- The org vault as the browser views read it (helpers/org/web/init.lua).
--
-- One walk over the agenda files builds the entry list; the views below are
-- the org.nvim agenda views of lua/terminal_plugins/org.nvim.lua, sectioned
-- and sorted the way that config draws them:
--
--   board      the `w` board -- In progress, one section per classification
--              tag, the untagged rest, Done (most recently closed first)
--   agenda     the `§` agenda -- the current week day by day, Monday first,
--              with what is overdue above it and the weeks either side of it
--              below, drawn from org.nvim's own agenda finder: the dates on
--              SCHEDULED and DEADLINE, the plain and inactive timestamps of
--              a date tree, diary lines
--   open       the `o` list, one section per project file
--   flight     the `f` list -- NEXT, TEST and WARN, one section per
--              classification tag (the bug / feat / chore sections, the
--              untagged rest last), each with NEXT first
--   runs       the omp instances running now -- the panes the launcher
--              marked, each with what it was asked, how long it has been
--              going and the last step of its transcript. Not an agenda
--              view: its rows are tmux panes (helpers/org/web/live.lua), so
--              the client draws them from the payload's `live.instances`
--   state      the `g` list -- one section per open state
--   priority   the `p` list -- A, then B
--   wayfinder  the `y` view -- the charted map as a tree, then one section
--              per ticket kind
--
-- The headlines come from org.nvim's own parse (`org.files.get`, which reads
-- a loaded buffer before the disk), so TODO keywords, tags, planning dates
-- and the CLOSED stamp mean what they mean in the editor. The last-changed
-- date is helpers/org/changed.lua's, the same one the TUI columns show.
local M = {}

-- The board's section order (lua/terminal_plugins/org.nvim.lua's
-- BOARD_STATE_ORDER): the states asking for action first.
local BOARD_STATES = { 'TEST', 'NEXT', 'TODO', 'PEND', 'WARN' }
local BOARD_RANK = {}
for i, state in ipairs(BOARD_STATES) do
  BOARD_RANK[state] = i
end

-- The group view's per-state order (GROUP_STATE_ORDER): TEST first, TODO
-- last.
local GROUP_STATES = { 'TEST', 'NEXT', 'PEND', 'WARN', 'TODO' }

local CLASS_TAGS = { 'bug', 'feat', 'chore' }

--- Path shown in the sidebar: under ~/org, relative to it.
---@param path string
---@return string
local function relative(path)
  local home = vim.fs.normalize(vim.fn.expand '~')
  local org = home .. '/org/'
  if vim.startswith(path, org) then
    return path:sub(#org + 1)
  end
  if vim.startswith(path, home .. '/') then
    return path:sub(#home + 2)
  end
  return path
end

--- The ids the entry's own section names, in order: the `[[id:…]]` links of
--- its body, which is where a hand-back's Related bullet and a wayfinder
--- map's decisions line sit. Not the children's: a link belongs to the
--- headline that wrote it.
---@param hl org.Headline
---@return string[]
local function ids_named(hl)
  local ids = {}
  for _, line in ipairs(hl:body_lines()) do
    for target in line:gmatch '%[%[id:([%w%-]+)%]' do
      ids[#ids + 1] = target
    end
  end
  return ids
end

--- Everything the views need about one headline.
---@param hl org.Headline
---@param ctx table shared per-file data: path, rel, project, open keywords
---@return table|nil entry
local function entry_of(hl, ctx)
  local changed = require 'helpers.org.changed'
  local latest = changed.latest(hl)
  local own_tags = hl.tags or {}
  local all_tags = hl:get_tags()
  local wf, wf_kind
  for _, tag in ipairs(all_tags) do
    if tag == 'wf' or tag:match '^wayfinder' then
      wf = true
    end
    wf_kind = wf_kind or tag:match '^wf_(%w+)$'
    if tag:match '^wayfinder_' then
      wf_kind = tag:match '^wayfinder_(%w+)$'
    end
  end
  local title = hl:plain_title()
  local cookie = hl.title:match '%[%d*/%d*%]' or hl.title:match '%[%d*%%%]'
  local deadline, scheduled = hl:deadline(), hl:scheduled()
  -- the day the agenda view files the entry under: the deadline it carries,
  -- else the one it was scheduled for -- the date its own line shows
  local when = deadline or scheduled
  local ancestors = {}
  local p = hl.parent
  while p do
    ancestors[#ancestors + 1] = p.line
    p = p.parent
  end
  return {
    file = ctx.path,
    rel = ctx.rel,
    project = require('helpers.org.project').item_name(hl) or ctx.project,
    line = hl.line,
    level = hl.level,
    parent = hl.parent and hl.parent.line or nil,
    ancestors = ancestors,
    todo = hl.todo,
    done = hl:is_done(),
    priority = hl.priority,
    title = title,
    cookie = cookie,
    tags = own_tags,
    id = hl.properties and hl.properties.ID or nil,
    session = hl.properties and hl.properties.OMP_SESSION or nil,
    deadline = deadline and deadline:to_string() or nil,
    scheduled = scheduled and scheduled:to_string() or nil,
    day = when and when:days() or nil,
    at = when and when:minutes() or nil,
    closed = hl:closed() and hl:closed():to_string() or nil,
    changed = changed.label(hl),
    changed_at = latest and latest:minutes() or nil,
    wf = wf or false,
    wf_kind = wf_kind,
    links = ids_named(hl),
  }
end

local cache
local cached_at = 0
-- the agenda sections, cached beside the entries: the finder walks every file
-- of the selection, and the page asks for the payload on every entry it opens
local agenda_cache = { key = false }

local function collect()
  local files = require('org.files').agenda_file_paths()
  local project = require 'helpers.org.project'
  local entries, projects = {}, {}
  for _, path in ipairs(files) do
    local skip = path:match '%.org_archive$' or path:find('/archive/', 1, true)
    local ok, file = false, nil
    if not skip then
      ok, file = pcall(function()
        return require('org.files').get(path)
      end)
    end
    if ok and file then
      local ctx = {
        path = path,
        rel = relative(path),
        project = project.file_title(path),
      }
      local seen = false
      local walked = pcall(function()
        local function walk(hls)
          for _, hl in ipairs(hls or {}) do
            if not hl:is_hidden_by_ancestor() then
              if hl.todo then
                local entry = entry_of(hl, ctx)
                if entry then
                  entries[#entries + 1] = entry
                  seen = true
                end
              end
              walk(hl.children)
            end
          end
        end
        walk(file.children)
      end)
      if not walked then
        -- one unreadable file must not blank the whole dashboard
        entries = vim.tbl_filter(function(entry)
          return entry.file ~= path
        end, entries)
        seen = false
      end
      if seen then
        projects[#projects + 1] = {
          path = path,
          rel = ctx.rel,
          name = ctx.project,
        }
      end
    end
  end
  table.sort(projects, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return entries, projects
end

--- The entry list and the project list, cached for a moment so a page load
--- (data + one entry detail) does not walk the vault twice. The server
--- invalidates it when an org file changes.
---@return table[] entries, table[] projects
function M.entries()
  local now = (vim.uv or vim.loop).hrtime() / 1e6
  if cache and now - cached_at < 2000 then
    return cache.entries, cache.projects
  end
  local entries, projects = collect()
  cache = { entries = entries, projects = projects }
  cached_at = now
  return entries, projects
end

function M.invalidate()
  cache = nil
  agenda_cache.key = false
end

--- One entry of the current list, by file and line (or `:ID:`).
---@param file string
---@param line integer|nil
---@param id string|nil
---@return table|nil
function M.find(file, line, id)
  local entries = M.entries()
  for _, entry in ipairs(entries) do
    if entry.file == file and ((id and entry.id == id) or (not id and entry.line == line)) then
      return entry
    end
  end
  return nil
end

--- The entry carrying `id`, wherever it lives, or nil when the vault no longer
--- has it (a ticket archived out of the vault still has a run).
---@param id string|nil
---@return table|nil
function M.by_id(id)
  if not id then
    return nil
  end
  for _, entry in ipairs(M.entries()) do
    if entry.id == id then
      return entry
    end
  end
  return nil
end

--- The instances running now, each with the entry of the ticket it is on
--- attached when the vault still has that ticket: the Runs view links a row
--- to what the run is working on.
---@return table[]
function M.instances()
  local out = require('helpers.org.web.live').instances()
  for _, instance in ipairs(out) do
    if instance.ticket then
      instance.entry = M.by_id(instance.ticket)
    end
  end
  return out
end

--- Absolute minutes are comparable across entries; a missing date sorts
--- last.
---@param a table
---@param b table
local function by_priority(a, b)
  if a.priority ~= b.priority then
    return (a.priority or 'Z') < (b.priority or 'Z')
  end
  return a.title:lower() < b.title:lower()
end

local function by_state_rank(a, b)
  local ra, rb = BOARD_RANK[a.todo] or 99, BOARD_RANK[b.todo] or 99
  if ra ~= rb then
    return ra < rb
  end
  return by_priority(a, b)
end

local function by_changed(a, b)
  if a.changed_at ~= b.changed_at then
    return (a.changed_at or -1) > (b.changed_at or -1)
  end
  return false
end

--- Indent every entry under the nearest ancestor the section also lists, so
--- a ticket shows under its parent and a lone one starts at the margin.
---@param items table[] already ordered
---@return table[]
local function indent(items)
  local listed = {}
  for _, entry in ipairs(items) do
    listed[entry.file .. '#' .. entry.line] = true
  end
  local out = {}
  for _, entry in ipairs(items) do
    local depth = 0
    for _, line in ipairs(entry.ancestors) do
      if listed[entry.file .. '#' .. line] then
        depth = depth + 1
      end
    end
    -- a copy: the same entry is listed by several views, and each of them
    -- nests it at its own depth
    out[#out + 1] = vim.tbl_extend('force', entry, { depth = depth })
  end
  return out
end

---@param entries table[]
---@param pred fun(entry: table): boolean
---@return table[]
local function pick(entries, pred)
  local out = {}
  for _, entry in ipairs(entries) do
    if pred(entry) then
      out[#out + 1] = entry
    end
  end
  return out
end

local function has_tag(entry, tag)
  for _, t in ipairs(entry.tags or {}) do
    if t == tag then
      return true
    end
  end
  return false
end

local function has_class(entry)
  for _, tag in ipairs(CLASS_TAGS) do
    if has_tag(entry, tag) then
      return true
    end
  end
  return false
end

local function is_open(entry)
  return not entry.done
end

--- The entries one selection shows: a project's file, or every agenda file
--- for 'all' (what the payload's `file` argument means).
---@param entries table[]
---@param file string|nil
---@return table[]
local function scope(entries, file)
  if file and file ~= '' and file ~= 'all' then
    return pick(entries, function(e)
      return e.file == file
    end)
  end
  return entries
end

--- The sections of one view over `entries`.
---@param entries table[]
---@return table[] sections
local function board(entries)
  local open = pick(entries, is_open)
  local progress = pick(open, function(e)
    return e.todo == 'NEXT' or e.todo == 'TEST'
  end)
  table.sort(progress, by_state_rank)
  local sections = {}
  if #progress > 0 then
    sections[#sections + 1] = { title = 'In progress', icon = '▶', items = indent(progress) }
  end
  local labels = { bug = 'Bugs, open', feat = 'Features, open', chore = 'Chores, open' }
  for _, tag in ipairs(CLASS_TAGS) do
    local items = pick(open, function(e)
      return has_tag(e, tag) and e.todo ~= 'NEXT' and e.todo ~= 'TEST'
    end)
    table.sort(items, by_priority)
    if #items > 0 then
      sections[#sections + 1] = { title = labels[tag], icon = '◆', items = indent(items) }
    end
  end
  local untagged = pick(open, function(e)
    return not has_class(e) and e.todo ~= 'NEXT' and e.todo ~= 'TEST'
  end)
  table.sort(untagged, by_priority)
  if #untagged > 0 then
    sections[#sections + 1] = { title = 'Untagged, open', icon = '○', items = indent(untagged) }
  end
  local all_done = pick(entries, function(e)
    return e.done
  end)
  table.sort(all_done, by_changed)
  local done = vim.list_slice(all_done, 1, 100)
  if #done > 0 then
    sections[#sections + 1] = {
      title = 'Done',
      icon = '✓',
      rule = true,
      items = indent(done),
      note = #all_done > #done and ('%d more'):format(#all_done - #done) or nil,
    }
  end
  return sections
end

---@param entries table[]
---@param projects table[]
---@return table[]
local function by_project(entries, projects)
  local sections = {}
  for _, project in ipairs(projects) do
    local items = pick(entries, function(e)
      return e.file == project.path and is_open(e)
    end)
    table.sort(items, by_state_rank)
    if #items > 0 then
      sections[#sections + 1] = { title = project.name, icon = '»', items = indent(items) }
    end
  end
  return sections
end

--- An open entry a run is on, has handed back for validation, or left in
--- trouble: the `f` list's NEXT, TEST and WARN. Every other open entry is
--- still waiting to be picked up, which is what the project rail's two
--- numbers count.
---@param entry table
---@return boolean
local function in_flight(entry)
  return not entry.done and (entry.todo == 'NEXT' or entry.todo == 'TEST' or entry.todo == 'WARN')
end

-- The `f` list read category first: one section per classification tag, the
-- untagged rest last -- the board's order and wording, cut to the in-flight
-- states -- and inside each the entry a run is on above the one waiting on
-- validation, then the troubled one (the `w` board's in-progress ranking,
-- which puts NEXT before TEST).
local FLIGHT_RANK = { NEXT = 1, TEST = 2, WARN = 3 }
local FLIGHT_LABELS = { bug = 'Bugs in flight', feat = 'Features in flight', chore = 'Chores in flight' }

local function by_flight(a, b)
  local ra, rb = FLIGHT_RANK[a.todo] or 99, FLIGHT_RANK[b.todo] or 99
  if ra ~= rb then
    return ra < rb
  end
  return by_priority(a, b)
end

local function flight(entries)
  local items = pick(entries, in_flight)
  local sections = {}
  for _, tag in ipairs(CLASS_TAGS) do
    local tagged = pick(items, function(e)
      return has_tag(e, tag)
    end)
    table.sort(tagged, by_flight)
    if #tagged > 0 then
      sections[#sections + 1] = { title = FLIGHT_LABELS[tag], icon = '◆', items = indent(tagged) }
    end
  end
  local rest = pick(items, function(e)
    return not has_class(e)
  end)
  table.sort(rest, by_flight)
  if #rest > 0 then
    sections[#sections + 1] = { title = 'Untagged in flight', icon = '○', items = indent(rest) }
  end
  return sections
end

-- The `§` week, drawn from org.nvim's own finder (org/agenda/items.lua's
-- `M.agenda`) rather than from the entries above: the editor's agenda lists
-- the appointments of a date tree, a plain timestamp, a scheduled or deadline
-- date and a diary line, and most of those carry no TODO keyword at all --
-- the entry walk only keeps the headlines that do. Going through the finder
-- is what makes the two views the same week, with the same times.
local function by_at(a, b)
  local aa, ab = a.at or math.huge, b.at or math.huge
  if aa ~= ab then
    return aa < ab
  end
  return by_priority(a, b)
end

--- "9:00-9:15" (org-agenda's `%t`), or "" for an item with no time of day.
---@param item org.AgendaItem
---@return string
local function time_label(item)
  local function hm(m)
    local h, mm = math.floor(m / 60), m % 60
    if h > 24 or (h == 24 and mm > 0) then
      return ('+%d:%02d'):format(h - 24, mm)
    end
    return ('%d:%02d'):format(h, mm)
  end
  if not item.time then
    return ''
  end
  if item.end_time and item.end_time > item.time then
    return hm(item.time) .. '-' .. hm(item.end_time)
  end
  return hm(item.time)
end

--- One row of the agenda. An item that comes from a headline reuses the entry
--- the walk above made of it, so the row keeps its project, its run button and
--- its live dot; an item no headline carries (a diary line) gets a bare row.
---@param item org.AgendaItem
---@param day integer
---@param entries_by_line table<string, table>
---@return table
local function agenda_row(item, day, entries_by_line)
  local entry = item.filename and entries_by_line[item.filename .. '#' .. tostring(item.lnum)] or nil
  local row = entry
    or {
      file = item.filename or '',
      rel = item.filename and relative(item.filename) or '',
      line = item.lnum,
      project = item.filename and require('helpers.org.project').file_title(item.filename) or (item.category or ''),
      ancestors = {},
    }
  local merged = vim.tbl_extend('force', row, {
    title = item.display_title or item.title or '',
    todo = item.todo,
    priority = item.priority,
    done = item.done == true,
    tags = item.tags or {},
    day = day,
    agenda = { time = time_label(item), type = item.type },
  })
  -- the entry a row reuses carries the day of its planning date, not the time
  -- of this item: the agenda line's time is the item's own, and an item with
  -- no time of day keeps a nil there so the client sorts it last
  merged.at = item.time
  return merged
end

--- The sections of the agenda view: what ran past its date above the week,
--- the seven days of it (a header each, entries or not), then the week ahead
--- and the week behind it below.
---@param file string|nil the selected project (`nil` or 'all' = every file)
---@param entries_by_line table<string, table>
---@return table[]
local function agenda(file, entries_by_line)
  local date = require 'org.date'
  local org_files = require 'org.files'
  local start = date.today()
  local today = start:days()
  local monday = today - (start:weekday() - 1)
  local sunday = monday + 6
  -- the fringe: the week behind this one and the week after it -- enough for
  -- the "Later" and "Earlier" sections, and no wider, so a daily appointment
  -- does not fill them with its own repeats a month out
  local from, to = monday - 7, sunday + 7
  local list = {}
  for _, path in ipairs(org_files.agenda_file_paths()) do
    if not file or file == '' or file == 'all' or path == file then
      local ok, f = pcall(org_files.get, path)
      if ok and f then
        list[#list + 1] = f
      end
    end
  end
  local ok, by_day = pcall(require('org.agenda.items').agenda, list, from, to, { today = today })
  if not ok then
    by_day = {}
  end
  local rows = {}
  for d = from, to do
    for _, item in ipairs(by_day[d] or {}) do
      rows[#rows + 1] = agenda_row(item, d, entries_by_line)
    end
  end
  local sections = {}
  -- the board's Done list cap: a bucket that would run past it says how much
  -- it left out instead of growing without limit
  local function section(title, icon, items, opts)
    opts = opts or {}
    -- a day of the week keeps its header even with nothing under it: the
    -- week reads as a week, the way the editor's agenda reads
    if #items == 0 and not opts.day then
      return
    end
    table.sort(items, opts.newest and function(a, b)
      return by_at(b, a)
    end or by_at)
    local shown = vim.list_slice(items, 1, 100)
    sections[#sections + 1] = {
      title = title,
      icon = icon,
      items = indent(shown),
      note = #items > #shown and ('%d more'):format(#items - #shown) or nil,
      label = opts.label,
      day = opts.day,
      today = opts.today or nil,
      -- the current minute: the client draws a "now" line among today's rows
      now = opts.now,
    }
  end

  -- what is late: an item that carries a keyword and is still open, its date
  -- behind it. A past appointment is not late, it just happened, and it stays
  -- on its own day where the week lists it
  section(
    'Overdue',
    '!',
    pick(rows, function(e)
      return e.day < today and not e.done and e.todo ~= nil
    end)
  )
  local now = date.now()
  local now_at = (now.hour or 0) * 60 + (now.min or 0)
  for d = monday, sunday do
    local day = date.from_days(d)
    -- a day gone by lists what was closed on it; its open work is Overdue,
    -- one section above, and a second copy here would say nothing new
    section(
      day:strftime '%A %d %B %Y',
      '◷',
      pick(rows, function(e)
        return e.day == d and (d >= today or e.done)
      end),
      {
        day = d,
        today = d == today,
        now = d == today and now_at or nil,
        label = { dow = day:strftime '%A', date = day:strftime '%d %B %Y' },
      }
    )
  end
  section(
    'Next week',
    '›',
    pick(rows, function(e)
      return e.day > sunday
    end)
  )
  -- the weeks behind the one on screen, latest first: the closed work that
  -- would otherwise leave the agenda for good
  section(
    'Earlier',
    '‹',
    pick(rows, function(e)
      return e.day < monday and e.done
    end),
    { newest = true }
  )
  return sections
end

local function state_sections(entries)
  local sections = {}
  for _, state in ipairs(GROUP_STATES) do
    local items = pick(entries, function(e)
      return is_open(e) and e.todo == state
    end)
    table.sort(items, by_priority)
    if #items > 0 then
      sections[#sections + 1] = { title = state, icon = '●', state = state, items = indent(items) }
    end
  end
  return sections
end

local function priority(entries)
  local sections = {}
  for _, level in ipairs { 'A', 'B' } do
    local items = pick(entries, function(e)
      return is_open(e) and e.priority == level
    end)
    table.sort(items, by_state_rank)
    if #items > 0 then
      sections[#sections + 1] = { title = 'Priority ' .. level, icon = '!', items = indent(items) }
    end
  end
  return sections
end

local function wayfinder(entries)
  local maps = pick(entries, function(e)
    return e.wf and is_open(e) and e.wf_kind == 'map'
  end)
  local sections = {}
  if #maps > 0 then
    -- the map and its tickets, in file order: parents before children, the
    -- way the route was charted
    local map_files = {}
    for _, map in ipairs(maps) do
      map_files[map.file] = true
    end
    local items = pick(entries, function(e)
      return e.wf and is_open(e) and map_files[e.file]
    end)
    table.sort(items, function(a, b)
      if a.file == b.file then
        return a.line < b.line
      end
      return a.file < b.file
    end)
    if #items > 0 then
      sections[#sections + 1] = { title = 'Wayfinder map, open', icon = '⌖', items = indent(items) }
    end
  end
  for _, kind in ipairs { 'research', 'prototype', 'grilling', 'task' } do
    local items = pick(entries, function(e)
      return is_open(e) and e.wf_kind == kind
    end)
    table.sort(items, by_state_rank)
    if #items > 0 then
      sections[#sections + 1] = { title = kind:gsub('^%l', string.upper), icon = '◇', items = indent(items) }
    end
  end
  return sections, #maps > 0
end

local VIEWS = {
  { key = 'board', title = 'Board', icon = '▦' },
  -- the board as a picture: every open ticket a node, the nesting it sits in
  -- and the `[[id:…]]` links its body wrote the edges (M.graph)
  { key = 'graph', title = 'Graph', icon = '◉' },
  { key = 'agenda', title = 'Agenda', icon = '◷' },
  { key = 'flight', title = 'In flight', icon = '▶' },
  -- the one view with nothing of the vault in it: what is running right now
  -- is a set of tmux panes (helpers/org/web/live.lua), so its rows come from
  -- the live half of the payload, not from a section of entries
  { key = 'runs', title = 'Runs', icon = '⦿' },
  { key = 'open', title = 'All open', icon = '≡' },
  { key = 'state', title = 'By state', icon = '●' },
  { key = 'priority', title = 'Priorities', icon = '!' },
  { key = 'wayfinder', title = 'Wayfinder', icon = '⌖' },
}

--- Payload for the dashboard: every view, already sectioned, over the
--- selected project (`file` nil = every agenda file).
---@param file string|nil
---@return table
function M.payload(file)
  local entries, projects = M.entries()
  local scoped = scope(entries, file)
  local counts = {}
  local total, done, moving, waiting = 0, 0, 0, 0
  for _, entry in ipairs(entries) do
    local count = counts[entry.file]
    if not count then
      count = { open = 0, done = 0, flight = 0, pending = 0 }
      counts[entry.file] = count
    end
    if entry.done then
      count.done = count.done + 1
      done = done + 1
    else
      count.open = count.open + 1
      if in_flight(entry) then
        count.flight = count.flight + 1
        moving = moving + 1
      else
        count.pending = count.pending + 1
        waiting = waiting + 1
      end
    end
    total = total + 1
  end
  local instances = M.instances()
  local views = {}
  local by_line = {}
  for _, entry in ipairs(entries) do
    by_line[entry.file .. '#' .. tostring(entry.line)] = entry
  end
  local selection = file and file ~= '' and file or 'all'
  local agenda_sections
  local now_ms = (vim.uv or vim.loop).hrtime() / 1e6
  if agenda_cache.key == selection and now_ms - agenda_cache.at < 2000 then
    agenda_sections = agenda_cache.sections
  else
    agenda_sections = agenda(selection, by_line)
    agenda_cache = { key = selection, at = now_ms, sections = agenda_sections }
  end
  for _, view in ipairs(VIEWS) do
    local sections
    local count
    if view.key == 'board' then
      sections = board(scoped)
    elseif view.key == 'agenda' then
      sections = agenda_sections
    elseif view.key == 'open' then
      sections = by_project(scoped, projects)
    elseif view.key == 'flight' then
      sections = flight(scoped)
    elseif view.key == 'runs' then
      -- its rows are the live instances below, not entries: the tab is here
      -- for its name and its count, and the client draws the list from
      -- `out.live.instances`
      sections = {}
      count = #instances
    elseif view.key == 'graph' then
      -- a picture, not a list: the tab is here for its name and its count,
      -- and the client asks /api/graph for the nodes and edges
      sections = {}
      count = #pick(scoped, is_open)
    elseif view.key == 'state' then
      sections = state_sections(scoped)
    elseif view.key == 'priority' then
      sections = priority(scoped)
    else
      sections = wayfinder(scoped)
    end
    views[#views + 1] = {
      key = view.key,
      title = view.title,
      icon = view.icon,
      sections = sections,
      count = count,
    }
  end
  local open_total = 0
  for _, count in pairs(counts) do
    open_total = open_total + count.open
  end
  local out = {
    generated = os.date '%Y-%m-%d %H:%M:%S',
    selection = file or 'all',
    projects = {},
    totals = { open = open_total, done = done, all = total, flight = moving, pending = waiting },
    views = views,
    -- every ticket of the vault, whatever the rail is set to: the search
    -- (`C-p` in the page) is the one list that ignores the selection, so a
    -- ticket from another project opens without a detour through the rail
    tickets = entries,
  }
  for _, project in ipairs(projects) do
    local count = counts[project.path] or { open = 0, done = 0, flight = 0, pending = 0 }
    out.projects[#out.projects + 1] = {
      path = project.path,
      rel = project.rel,
      name = project.name,
      open = count.open,
      done = count.done,
      flight = count.flight,
      pending = count.pending,
    }
  end
  -- what a run is on right now: the panes the launcher marked, and the last
  -- thing each running run's transcript holds (helpers/org/web/live.lua)
  local live = require 'helpers.org.web.live'
  local running = live.runs()
  out.live = {
    tickets = vim.tbl_keys(running.tickets),
    sessions = vim.tbl_keys(running.sessions),
    activity = {},
    instances = instances,
  }
  for _, entry in ipairs(scoped) do
    local key = entry.session
    if key and (running.sessions[key] or (entry.id and running.tickets[entry.id])) then
      out.live.activity[key] = live.activity(key)
    end
  end
  return out
end

-- The node key of an entry: its `:ID:` when it has one, else the place it
-- sits. Two tickets of one vault never share an id, and a headline the
-- launcher never touched still gets a node.
---@param entry table
---@return string
local function node_key(entry)
  return entry.id or (entry.file .. '#' .. tostring(entry.line))
end

--- The graph of one selection: every open ticket a node, and two kinds of
--- edge — the nesting a ticket sits in (`blocks`: the child is what blocks
--- the parent, the way a wayfinder tree is read) and the `id:` links its own
--- body wrote (`link`). A closed ticket one of them names comes along as a
--- node too, so the trace runs past the tickets that are finished.
---@param file string|nil
---@return table
function M.graph(file)
  local entries = M.entries()
  local scoped = scope(entries, file)
  local by_line, by_id = {}, {}
  for _, entry in ipairs(entries) do
    by_line[entry.file .. '#' .. tostring(entry.line)] = entry
    if entry.id then
      by_id[entry.id] = entry
    end
  end
  local nodes, seen, by_key = {}, {}, {}
  local function add(entry)
    local key = node_key(entry)
    if seen[key] then
      return key
    end
    seen[key] = true
    local node = {
      key = key,
      id = entry.id,
      title = entry.title,
      todo = entry.todo,
      done = entry.done,
      project = entry.project,
      rel = entry.rel,
      file = entry.file,
      line = entry.line,
      cookie = entry.cookie,
      session = entry.session,
      wf = entry.wf,
      wf_kind = entry.wf_kind,
      links = 0,
      backlinks = 0,
    }
    nodes[#nodes + 1] = node
    by_key[key] = node
    return key
  end
  local open = pick(scoped, is_open)
  for _, entry in ipairs(open) do
    add(entry)
  end
  -- one edge per pair of tickets: two bodies naming each other is one
  -- relation, and a ticket nested twice in a file cannot be
  local edges, drawn = {}, {}
  local function edge(source, target, kind)
    if source == target then
      return
    end
    local key = kind .. '\0' .. source .. '\0' .. target
    if drawn[key] then
      return
    end
    drawn[key] = true
    edges[#edges + 1] = { source = source, target = target, kind = kind }
  end
  for _, entry in ipairs(open) do
    -- the ticket's nearest ancestor that is a ticket too: an untagged
    -- headline between them is a grouping, not a dependency
    for _, ancestor in ipairs(entry.ancestors) do
      local parent = by_line[entry.file .. '#' .. tostring(ancestor)]
      if parent and not parent.done then
        edge(node_key(parent), node_key(entry), 'blocks')
        break
      end
    end
  end
  for _, entry in ipairs(open) do
    local from = node_key(entry)
    for _, id in ipairs(entry.links or {}) do
      local target = by_id[id]
      if target then
        local to = add(target)
        if to ~= from then
          edge(from, to, 'link')
          by_key[from].links = by_key[from].links + 1
          by_key[to].backlinks = by_key[to].backlinks + 1
        end
      end
    end
  end
  return {
    nodes = nodes,
    edges = edges,
    stats = { nodes = #nodes, edges = #edges, open = #open },
  }
end

return M
