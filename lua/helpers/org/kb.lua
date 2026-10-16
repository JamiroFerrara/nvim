-- The knowledge-base hub: ~/org/roam/index.org regenerated from the base.
--
-- Everything below the file's `* Index` headline is generated; everything above
-- it -- what the base is for, the shape, the vocabulary, the rules -- is
-- hand-written and left alone. `M.index()` walks `~/org/roam/documentation/`
-- (the file-for-file mirror of ~/org/projects/) and writes one link per
-- workstream and per finding, with counts and the unreviewed drafts on top, so
-- the hub is both the browsing surface and the review list. It is a rendering
-- of files that already exist, not something an agent writes, which is why it
-- cannot rot: `OrgKbIndex` (and the `kb` skill at the end of a consolidation
-- run) simply rebuilds it.
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

--- `[[id:…][title]]` for a node, or the bare title when it has no :ID: yet
--- (`<leader>olI` mints one).
---@param hl org.Headline
---@return string
local function link(hl)
  local id = hl:get_property('ID', false)
  local title = clean(hl:plain_title())
  if id and id:match '%S' then
    return string.format('[[id:%s][%s]]', vim.trim(id), title)
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

---@param hl org.Headline
---@return boolean
local function is_draft(hl)
  return vim.tbl_contains(all_tags(hl), 'kb_draft')
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

  local out, drafts, questions = {}, {}, {}
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
            if is_draft(f) then
              drafts[#drafts + 1] = string.format('- %s — %s', link(f), title)
            end
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
    string.format('%d file%s · %d workstream%s · %d finding%s · %d draft%s. Generated by `OrgKbIndex` (helpers/org/kb.lua) — edit above this headline, everything below is rebuilt.',
      #files, #files == 1 and '' or 's', topics, topics == 1 and '' or 's', findings, findings == 1 and '' or 's', #drafts, #drafts == 1 and '' or 's'),
  }
  if #drafts > 0 then
    head[#head + 1] = ''
    head[#head + 1] = string.format('Drafts awaiting review (%d) — written by a run, not yet blessed:', #drafts)
    head[#head + 1] = table.concat(drafts, '\n')
  end
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

function M.setup()
  vim.api.nvim_create_user_command('OrgKbIndex', M.index, {
    desc = 'Rebuild the knowledge-base hub (~/org/roam/index.org)',
  })
end

return M
