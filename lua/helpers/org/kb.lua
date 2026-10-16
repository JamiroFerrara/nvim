-- The knowledge-base hub: ~/org/roam/index.org regenerated from the base.
--
-- Everything below the file's `* Index` headline is generated; everything above
-- it -- what the base is for, the shape, the vocabulary, the rules -- is
-- hand-written and left alone. `M.index()` walks `~/org/roam/documentation/`
-- (the file-for-file mirror of ~/org/projects/) and writes one link per
-- workstream and per finding, with counts and the file's date. It is the
-- browsing surface, rendered from files that already exist; a rendering cannot
-- rot the way a hand-written index does: `OrgKbIndex` -- and the `kb` skill at
-- the end of a tidy run -- simply rebuilds it.
--
-- `M.ensure_ids` is the other half of "everything here is a node": a knowledge
-- base file gets an `:ID:` on every headline of level 2 or deeper when it is
-- saved, so a finding (or a topic) you write by hand is linkable the moment it
-- exists, exactly like the ones an agent writes.
local M = {}

local BASE = '~/org/roam'
local DOCS = BASE .. '/documentation'
local INDEX = BASE .. '/index.org'
local MARKER = '* Index'

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

--- A headline's own tags plus its inherited ones. `get_inherited_tags()` walks
--- the ancestors only -- it excludes the headline itself, like
--- `outline_path()` -- so a tag written on the finding must be read from
--- `hl.tags`, and a tag on its topic or file comes back from the inheritance.
---@param hl org.Headline
---@return string[]
local function all_tags(hl)
  local out = {}
  for _, t in ipairs(hl.tags or {}) do
    out[#out + 1] = t
  end
  for _, t in ipairs(hl:get_inherited_tags()) do
    out[#out + 1] = t
  end
  return out
end

--- A headline is a finding when it says something (a `kb_fact` or `kb_answer`
--- tag, its own or inherited from its topic) and has an identity to be linked
--- by.
---@param hl org.Headline
---@return boolean
local function is_finding(hl)
  local ids = hl:get_property('ID', false)
  if not (ids and ids:match '%S') then
    return false
  end
  local tags = all_tags(hl)
  return vim.tbl_contains(tags, 'kb_fact') or vim.tbl_contains(tags, 'kb_answer')
end

--- Every headline with an :ID: under `hl`, depth first.
---@param hl org.Headline
---@param out org.Headline[]
local function descendants(hl, out)
  for _, child in ipairs(hl.children or {}) do
    out[#out + 1] = child
    descendants(child, out)
  end
end

--- The generated section: one block per KB file, workstream by workstream.
---@return string[]
local function body()
  local files = vim.fn.glob(vim.fn.expand(DOCS) .. '/*.org', false, true)
  table.sort(files)

  local out, questions = {}, {}
  local findings, topics = 0, 0

  for _, path in ipairs(files) do
    local file = require('org.files').get(path)
    if file then
      local board = vim.fn.expand('~/org/projects/' .. vim.fn.fnamemodify(path, ':t'))
      local file_id = file.properties and file.properties.ID
      local title = clean(file.settings.title) ~= '' and clean(file.settings.title) or vim.fn.fnamemodify(path, ':t:r')
      local label = file_id and string.format('[[id:%s][%s]]', vim.trim(file_id), title) or title

      local blocks, mine, my_topics = {}, 0, 0
      for _, ws in ipairs(file.children or {}) do
        local nodes = {}
        descendants(ws, nodes)
        local ws_findings = vim.tbl_filter(is_finding, nodes)
        -- every workstream is listed, findings or not: an empty base still has
        -- to show what there is to fill in, which is the point of the hub
        local id = ws:get_property('ID', false)
        if #ws_findings > 0 or (id and id:match '%S') then
          my_topics = my_topics + 1
          local lines = { string.format('*** %s', link(ws)) }
          for _, f in ipairs(ws_findings) do
            mine = mine + 1
            if vim.tbl_contains(all_tags(f), 'kb_question') then
              questions[#questions + 1] = string.format('- %s — %s', link(f), title)
            end
            lines[#lines + 1] = string.format('  - %s  =%s=', link(f), table.concat(f:get_inherited_tags(), ':') ~= '' and ':' .. table.concat(f:get_inherited_tags(), ':') .. ':' or '')
          end
          blocks[#blocks + 1] = table.concat(lines, '\n')
        end
      end

      if #blocks > 0 then
        findings = findings + mine
        topics = topics + my_topics
        out[#out + 1] = string.format('** %s — %d workstream%s · %d finding%s', label, my_topics, my_topics == 1 and '' or 's', mine, mine == 1 and '' or 's')
        out[#out + 1] = string.format(
          '   [[file:%s][board]] · %s · updated %s',
          board,
          vim.fn.fnamemodify(path, ':t'),
          os.date('%Y-%m-%d', vim.fn.getftime(path))
        )
        out[#out + 1] = table.concat(blocks, '\n\n')
        out[#out + 1] = ''
      end
    end
  end

  local head = {
    string.format('%d file%s · %d workstream%s · %d finding%s. Generated by `OrgKbIndex` (helpers/org/kb.lua) — edit above this headline, everything below is rebuilt.',
      #files, #files == 1 and '' or 's', topics, topics == 1 and '' or 's', findings, findings == 1 and '' or 's'),
  }
  if #questions > 0 then
    head[#head + 1] = ''
    head[#head + 1] = string.format('Open questions (%d):', #questions)
    head[#head + 1] = table.concat(questions, '\n')
  end
  if #files == 0 then
    head[#head + 1] = ''
    head[#head + 1] = 'No file in `documentation/` yet: seed it from the boards (`~/org/scripts/roam-seed/seed.py --write`).'
  else
    head[#head + 1] = ''
    head[#head + 1] = table.concat(out, '\n')
  end
  return vim.split(table.concat(head, '\n'), '\n', { plain = true })
end

--- Rewrite ~/org/roam/index.org: keep everything above `* Index`, replace the
--- rest.
---@return integer lines written, integer files described
function M.index()
  local path = vim.fn.expand(INDEX)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= 'table' then
    require('org.utils').warn('org kb: cannot read ' .. INDEX)
    return 0, 0
  end

  local at
  for i, l in ipairs(lines) do
    if l:match '^%* Index%s*$' then
      at = i
      break
    end
  end
  local keep = at and vim.list_slice(lines, 1, at - 1) or lines
  while #keep > 0 and keep[#keep]:match '^%s*$' do
    table.remove(keep)
  end

  local out = keep
  out[#out + 1] = ''
  out[#out + 1] = MARKER
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

--- Give every headline of level 2 or deeper in `bufnr` an `:ID:` when it has
--- none, and return how many were minted. A knowledge-base file is a directory
--- of nodes, and a heading you type by hand is one of them from the moment you
--- write it — not only the headings an agent wrote. Level 1 is left alone: the
--- workstreams come from the mirror (`~/org/scripts/roam-seed/seed.py`) and
--- already carry theirs.
---@param bufnr integer
---@return integer
function M.ensure_ids(bufnr)
  local file = require('org.files').get_buffer(bufnr)
  local missing = {}
  for _, hl in ipairs(file.headlines or {}) do
    if hl.level >= 2 then
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

function M.setup()
  vim.api.nvim_create_user_command('OrgKbIndex', M.index, {
    desc = 'Rebuild the knowledge-base hub (~/org/roam/index.org)',
  })
  -- Everything in the base is a node: the files under the base's own
  -- directories get an :ID: on every headline of level 2 or deeper as they are
  -- saved. `BufWritePre`, so the ID is in the file the write puts on disk.
  vim.api.nvim_create_autocmd('BufWritePre', {
    pattern = { '*/org/roam/documentation/*.org', '*/org/roam/people/*.org', '*/org/roam/topics/*.org' },
    callback = function(args)
      local n = M.ensure_ids(args.buf)
      if n > 0 then
        require('org.utils').notify(string.format('org kb: %d node%s given an :ID:', n, n == 1 and '' or 's'))
      end
    end,
  })
end

return M
