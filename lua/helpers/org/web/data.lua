-- The org vault as the browser views read it (helpers/org/web/init.lua).
--
-- One walk over the agenda files builds the entry list; the views below are
-- the org.nvim agenda views of lua/terminal_plugins/org.nvim.lua, sectioned
-- and sorted the way that config draws them:
--
--   board      the `w` board -- In progress, one section per classification
--              tag, the untagged rest, Done (most recently closed first)
--   open       the `o` list, one section per project file
--   flight     the `f` list -- NEXT, TEST and WARN
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
    deadline = hl:deadline() and hl:deadline():to_string() or nil,
    scheduled = hl:scheduled() and hl:scheduled():to_string() or nil,
    closed = hl:closed() and hl:closed():to_string() or nil,
    changed = changed.label(hl),
    changed_at = latest and latest:minutes() or nil,
    wf = wf or false,
    wf_kind = wf_kind,
  }
end

local cache
local cached_at = 0

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

local function flight(entries)
  local items = pick(entries, function(e)
    return is_open(e) and (e.todo == 'NEXT' or e.todo == 'TEST' or e.todo == 'WARN')
  end)
  table.sort(items, by_state_rank)
  return { { title = 'Everything in flight', icon = '▶', items = indent(items) } }
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
  { key = 'flight', title = 'In flight', icon = '▶' },
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
  local scoped = entries
  if file and file ~= '' and file ~= 'all' then
    scoped = pick(entries, function(e)
      return e.file == file
    end)
  end
  local counts = {}
  local total, done = 0, 0
  for _, entry in ipairs(entries) do
    counts[entry.file] = counts[entry.file] or { open = 0, done = 0 }
    if entry.done then
      counts[entry.file].done = counts[entry.file].done + 1
      done = done + 1
    else
      counts[entry.file].open = counts[entry.file].open + 1
    end
    total = total + 1
  end
  local views = {}
  for _, view in ipairs(VIEWS) do
    local sections
    if view.key == 'board' then
      sections = board(scoped)
    elseif view.key == 'open' then
      sections = by_project(scoped, projects)
    elseif view.key == 'flight' then
      sections = flight(scoped)
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
    totals = { open = open_total, done = done, all = total },
    views = views,
  }
  for _, project in ipairs(projects) do
    local count = counts[project.path] or { open = 0, done = 0 }
    out.projects[#out.projects + 1] = {
      path = project.path,
      rel = project.rel,
      name = project.name,
      open = count.open,
      done = count.done,
    }
  end
  return out
end

return M
