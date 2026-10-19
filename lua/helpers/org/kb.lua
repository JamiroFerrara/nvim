-- The knowledge-base hub: ~/org/roam/index.org regenerated from the base.
--
-- The file is its own header plus the tree: the property drawer, `#+title:` and
-- `#+filetags:` at the top are kept as they are, and every headline below them
-- is replaced by what `M.index()` renders -- one entry per file, its
-- workstreams, and the findings of each workstream as links. Nothing else: no
-- preamble, no `* Index` wrapper, no summary line, no separators. What the base
-- is and how it works is ~/org/WORKFLOW.org's business.
--
-- Being a rendering of files that already exist, it cannot rot the way a
-- hand-written index does: `OrgKbIndex` -- and the `kb` skill at the end of a
-- tidy run -- simply rebuilds it.
--
-- `M.ensure_ids` is the other half of "everything here is a node": a knowledge
-- base file gets an `:ID:` on every headline of level 2 or deeper when it is
-- saved, so a finding (or a topic) you write by hand is linkable the moment it
-- exists, exactly like the ones an agent writes.
local M = {}

local BASE = '~/org/roam'
local DOCS = BASE .. '/documentation'
local INDEX = BASE .. '/index.org'

--- The startup visibility every file of the base opens with, the same keyword
--- the boards carry.
local STARTUP = '#+STARTUP: show2levels logdone logdrawer'

--- Link descriptions carry no brackets and stay on one line, or the link
--- breaks the moment a title contains one. A title like "`[[` completes nodes"
--- also loses the backtick pair its brackets were wearing, so it does not read
--- as ``` `` ``` once the brackets are gone.
---@param s string
---@return string
local function clean(s)
  return vim.trim((s or ''):gsub('[%[%]]', ''):gsub('`%s*`', ''):gsub('%s+', ' '))
end

--- `[[id:…][title]]` for a node, or a `file:` link to the headline when it has
--- no `:ID:` yet: a heading written into the base by hand gets its `:ID:` on
--- save (`M.ensure_ids`), but an entry in the hub is a link either way — a
--- level-3 header is a node you can jump to, never plain text.
---@param hl org.Headline
---@return string
local function link(hl)
  local id = hl:get_property('ID', false)
  local title = clean(hl:plain_title())
  if id and id:match '%S' then
    return string.format('[[id:%s][%s]]', vim.trim(id), title)
  end
  local path = hl.file and hl.file.filename
  if path and path ~= '' then
    return string.format('[[file:%s::*%s][%s]]', vim.fn.fnamemodify(path, ':~'), hl:plain_title(), title)
  end
  return title
end

--- The link target of a pointer headline -- `** [[id:…][Topic]]`, the shape a
--- project file uses to depend on a topic kept in `topics/` -- or nil when the
--- headline carries its own text.
---@param hl org.Headline
---@return string|nil
local function pointer(hl)
  local target = (hl.title or ''):match '^%[%[([^%]]-)%]%['
  if target and target:match '%S' then
    return vim.trim(target)
  end
  return nil
end

--- `[[id:…][title]]` for `hl`, following its pointer when it is one: a
--- workstream lists the topics it depends on, and the link goes where the
--- pointer goes.
---@param hl org.Headline
---@return string
local function entry(hl)
  local target = pointer(hl)
  if target then
    return string.format('[[%s][%s]]', target, clean(hl:plain_title()))
  end
  return link(hl)
end

--- `[[id:…][title]]` for a file's node, or the bare title when it has none.
---@param path string
---@param file org.File
---@return string
local function file_link(path, file)
  local title = clean(file.settings.title) ~= '' and clean(file.settings.title) or vim.fn.fnamemodify(path, ':t:r')
  local id = file.properties and file.properties.ID
  if id and id:match '%S' then
    return string.format('[[id:%s][%s]]', vim.trim(id), title)
  end
  return title
end

--- The hub: one section per kind of file, and under a project its workstreams
--- with the topics each one depends on. A topic entry says which projects use
--- it, the one thing a shared node cannot show by itself. Nothing else: no
--- counts, no summary, no board links, no prose -- the file's own header carries
--- what little of that belongs here, and what the base is lives in
--- ~/org/WORKFLOW.org.
---@return string[]
local function body()
  local out = {}
  local used_by = {} -- topic id -> { project title, ... }

  --- A pointer records who depends on what; `id:` is the prefix, the id is the
  --- key.
  local function note_use(target, project)
    local key = target:match '^id:(.+)$' or target
    local t = used_by[key] or {}
    used_by[key] = t
    if not vim.tbl_contains(t, project) then
      t[#t + 1] = project
    end
  end

  --- `hl`'s children at `depth`, walking into the ones that carry their own
  --- text. A pointer's children live in the file it points at, so there is
  --- nothing below it here.
  local function children(hl, depth, acc, project)
    for _, child in ipairs(hl.children or {}) do
      local target = pointer(child)
      if target then
        note_use(target, project)
      end
      acc[#acc + 1] = string.format('%s %s', string.rep('*', depth), entry(child))
      if not target then
        children(child, depth + 1, acc, project)
      end
    end
  end

  local function files(dir)
    local found = vim.fn.glob(vim.fn.expand(BASE .. '/' .. dir) .. '/*.org', false, true)
    table.sort(found)
    return found
  end

  -- projects: the file, its workstreams, the topics they depend on
  local projects = {}
  for _, path in ipairs(files 'documentation') do
    local file = require('org.files').get(path)
    if file then
      local title = clean(file.settings.title) ~= '' and clean(file.settings.title) or vim.fn.fnamemodify(path, ':t:r')
      local acc = {}
      for _, ws in ipairs(file.children or {}) do
        if clean(ws:plain_title()):lower() == title:lower() then
          -- the file entry stands for this workstream: its children come up
          children(ws, 3, acc, title)
        else
          acc[#acc + 1] = string.format('*** %s', entry(ws))
          children(ws, 4, acc, title)
        end
      end
      -- the file exists, so the project is listed even when it has nothing
      -- under it yet: a project with an empty base is a project to fill in
      projects[#projects + 1] = { '** ' .. file_link(path, file), acc }
    end
  end

  if #projects > 0 then
    out[#out + 1] = '* Projects'
    for _, project in ipairs(projects) do
      out[#out + 1] = project[1]
      for _, l in ipairs(project[2]) do
        out[#out + 1] = l
      end
    end
  end

  -- topics: the shared nodes, each saying who depends on it
  local topics = {}
  for _, path in ipairs(files 'topics') do
    local file = require('org.files').get(path)
    if file then
      local label = file_link(path, file)
      local id = file.properties and file.properties.ID
      local users = id and used_by[vim.trim(id)]
      if users and #users > 0 then
        label = label .. ' — used by ' .. table.concat(users, ', ')
      end
      topics[#topics + 1] = '** ' .. label
    end
  end
  if #topics > 0 then
    out[#out + 1] = '* Topics'
    for _, l in ipairs(topics) do
      out[#out + 1] = l
    end
  end

  -- people: leaves, one node each
  local people = {}
  for _, path in ipairs(files 'people') do
    local file = require('org.files').get(path)
    if file then
      people[#people + 1] = '** ' .. file_link(path, file)
    end
  end
  if #people > 0 then
    out[#out + 1] = '* People'
    for _, l in ipairs(people) do
      out[#out + 1] = l
    end
  end

  if #out == 0 then
    out[#out + 1] = 'Nothing in the base yet: seed it from the boards (`~/org/scripts/roam-seed/seed.py --write`).'
  end
  return out
end

--- Rewrite ~/org/roam/index.org: keep its header -- the property drawer, the
--- `#+title:` and `#+filetags:` keywords, and anything else above the first
--- headline -- and replace every headline below with the tree. The header is the
--- only part to edit by hand; anything written *under* it is lost on the next
--- rebuild.
---@return integer lines written, integer files described
function M.index()
  local path = vim.fn.expand(INDEX)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' then
    require('org.utils').warn('org kb: cannot read ' .. INDEX)
    return 0, 0
  end

  local at = #lines + 1
  for i, l in ipairs(lines) do
    if l:match '^%*+ ' then
      at = i
      break
    end
  end
  local out = vim.list_slice(lines, 1, at - 1)
  while #out > 0 and out[#out]:match '^%s*$' do
    table.remove(out)
  end
  for _, l in ipairs(body()) do
    out[#out + 1] = l
  end

  local wrote = vim.fn.writefile(out, path)
  if wrote ~= 0 then
    require('org.utils').warn('org kb: cannot write ' .. INDEX)
    return 0, 0
  end
  local described = #vim.fn.glob(vim.fn.expand(DOCS) .. '/*.org', false, true)
  require('org.utils').notify(string.format('org kb: index rebuilt — %d file(s), %d lines', described, #out))
  return #out, described
end

--- Give every content headline of level 2 or deeper in `bufnr` an `:ID:` when
--- it has none, and return how many were minted. A pointer headline --
--- `** [[id:…][Topic]]` -- gets none: it is the project's reference to a node
--- that lives in `topics/`, not a node of its own.
---@param bufnr integer
---@return integer
function M.ensure_ids(bufnr)
  local file = require('org.files').get_buffer(bufnr)
  local missing = {}
  for _, hl in ipairs(file.headlines or {}) do
    if hl.level >= 2 and not pointer(hl) then
      local id = hl:get_property('ID', false)
      if not (id and id:match '%S') then
        missing[#missing + 1] = hl.line
      end
    end
  end
  if #missing == 0 then
    return 0
  end
  -- entry_put adds the drawer, which inserts lines: bottom-up, so the line
  -- numbers still to come are the ones the parse gave us
  local props, id = require 'org.properties', require 'org.id'
  for i = #missing, 1, -1 do
    props.entry_put(bufnr, missing[i], 'ID', id.new_id())
  end
  return #missing
end

--- Give `bufnr` the `#+STARTUP:` every file of the base opens with -- the one
--- the boards carry -- above the first blank line or headline, with the file's
--- other keywords. Added when missing only: a value of your own is left alone.
--- Returns true when it was added.
---@param bufnr integer
---@return boolean
function M.ensure_startup(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, l in ipairs(lines) do
    if l:match '^#%+STARTUP:' then
      return false
    end
  end
  local at = #lines
  for i, l in ipairs(lines) do
    if l:match '^%s*$' or l:match '^%*+ ' then
      at = i - 1
      break
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, at, at, false, { STARTUP })
  return true
end

function M.setup()
  vim.api.nvim_create_user_command('OrgKbIndex', M.index, {
    desc = 'Rebuild the knowledge-base hub (~/org/roam/index.org)',
  })
  -- A project file is where the ids matter: its workstreams and its content
  -- headings are what everything else links by. A pointer heading is not a node
  -- (the topic it names is), so it gets none.
  vim.api.nvim_create_autocmd('BufWritePre', {
    pattern = '*/org/roam/documentation/*.org',
    callback = function(args)
      M.ensure_startup(args.buf)
      local n = M.ensure_ids(args.buf)
      if n > 0 then
        require('org.utils').notify(string.format('org kb: %d node%s given an :ID:', n, n == 1 and '' or 's'))
      end
    end,
  })
  -- Every other file of the base is a document: the file is the node and its
  -- sections are structure, so only the startup visibility is ensured.
  vim.api.nvim_create_autocmd('BufWritePre', {
    pattern = { '*/org/roam/topics/*.org', '*/org/roam/people/*.org' },
    callback = function(args)
      M.ensure_startup(args.buf)
    end,
  })
  -- The hub's header is yours, so only the keyword is ensured there: an :ID: on
  -- a heading of the tree would be a node the next rebuild throws away.
  vim.api.nvim_create_autocmd('BufWritePre', {
    pattern = '*/org/roam/index.org',
    callback = function(args)
      M.ensure_startup(args.buf)
    end,
  })
end

return M
