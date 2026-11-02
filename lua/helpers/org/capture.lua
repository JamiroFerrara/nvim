-- Capture-task destination for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua). The Task template asks where the entry
-- goes before the note is typed, and stores it there directly, instead of
-- dropping it in refile.org and refiling it again.
--
-- The cwd decides first: helpers/org/project.lua resolves the working
-- directory to its project (a `#+PROJECT_DIRS:` / `:PROJECT_DIRS:` claim,
-- else the nearest `.git` root) and the capture goes there, with no prompt.
-- Only when the cwd names no project does the picker run: the flat list of
-- level-1 headlines of the project files, no outline path, no whole-file
-- entries.
--
-- The destination is an outline path (`olp`), not a title: a project can be
-- a headline inside a shared file, and a title match would land on the first
-- same-named headline anywhere in it. The template carries `olp` instead of
-- `headline` for that reason.
--
-- This is the write side, so a `.git`-derived project file that does not
-- exist yet is created here (project.ensure) -- looking at a project (`£`,
-- `°`) never creates one, and neither does anything create a headline.
-- `pick` memoizes the choice so the template's `target` and `olp` read it
-- and the resolution runs once per capture. Cancelling the picker aborts the
-- capture (utils.abort), so nothing lands in the default notes file.
--
-- `setup` also registers `header_first`, the org.nvim store filter that keeps
-- the Task template's date header directly under the captured entry's
-- headline (see its docstring), and `hook` is the Task template's `hook`: it
-- keeps the capture buffer itself in that order as the entry is typed.
--
-- `capture_tags`, the other store filter, is the file/header scope of default
-- tags: whatever the destination inherits -- the target headline's whole set
-- (`#+FILETAGS:` of its file, its ancestors' tags, its own), or the file's
-- `#+FILETAGS:` alone for a capture landing at file level -- is appended to
-- the captured entry's headline. A project file carrying `#+FILETAGS: allitude`
-- and a `PMS` headline tagged `:pms:` therefore captures `:allitude:pms:`, the
-- same set the agenda would have shown the entry anyway through org tag
-- inheritance; the tags are written, not merely inherited.
-- Both capture paths that reach this store (the `^` Task capture and the
-- `c` / <leader>aC capture-under-entry, `M.under`, from the TODO view and
-- from `c` on a headline in an org file) go through the filter, so the
-- setting covers either way in.
--
-- `capture_autotags` (helpers/org/autotags.lua) is the third store filter:
-- the words the entry's own text carries it tags the entry with, so a
-- capture that says "fix the crash" lands `:bug:` without a keypress. The
-- map is word -> tag, the default one in the plugin's capture options, and a
-- project file replaces it for itself with `#+AUTOTAGS: word=tag ...`.
--
-- The stock `%a` line -- the link back to the entry the capture was started
-- from -- is not always the template's: `origin_link` answers whether this
-- capture keeps it, and the Task template (org.nvim.lua) asks before
-- spelling the line out. Only a capture started in a file keeps it, so a
-- capture made in the TODO view -- or in any other view -- does not carry
-- the text of the node at point into its own body, in the capture buffer or
-- after storing. `M.under` (the `c` / <leader>aC capture-under-entry)
-- builds on the same template, so either way in obeys the same rule.
--
-- A capture started in Visual mode carries the selection: `M.selection`
-- turns it into a `#+begin_src` block of the buffer's language, and the
-- template's `%i` puts it at the end of the entry. `^` in Visual mode
-- (`M.task`) and the roam capture below both go through it, so the code a
-- note is about travels with the note instead of being retyped.
--
-- `M.roam` is the other way in (`<C-c><C-n>`, `C-c C-n` in a board file):
-- the `r` template of the config, whose destination is a place in the
-- knowledge base picked from a fuzzy finder over every file of ~/org/roam
-- and every headline in it, its entry a plain headline -- no TODO keyword,
-- since a note is not a ticket -- with the same `%a` link back and the same
-- selection block. `M.roam_refile` is its twin inside a capture:
-- `<C-c><C-n>` stores the entry the capture holds at the destination the
-- template names, moves it under the node picked there, and takes the TODO
-- keyword off its headline on the way. Only the Task template starts an omp
-- run when its capture is stored (helpers/org/mappings.lua), and neither
-- the refile nor `<C-c><C-c>` (the capture's own save) is a write, so
-- nothing starts a run on either.
local M = {}

local dest

--- Ask for the destination project. Returns the memoized `{ file, olp }`
--- (nil when the pick was cancelled or there was nothing to offer).
function M.pick()
  local utils = require 'org.utils'
  dest = nil
  local project = require 'helpers.org.project'
  local current = project.current()
  if current and project.ensure(current) then
    dest = { file = current.file, olp = project.olp(current) }
    return dest
  end
  local targets = require('org.refile').targets {
    targets = { { files = '~/org/projects/*.org', max_level = 1 } },
    bufnr = vim.api.nvim_get_current_buf(),
  }
  local headlines = {}
  for _, t in ipairs(targets) do
    -- whole-file targets carry no line number; keep headlines only
    if t.lnum then
      headlines[#headlines + 1] = t
    end
  end
  if #headlines == 0 then
    utils.warn 'capture: no level-1 headline in ~/org/projects/*.org'
    return nil
  end
  local choice = utils.select(headlines, {
    prompt = 'Task to',
    kind = 'org_capture_target',
    format_item = function(t)
      return string.format('%s -> %s', vim.fn.fnamemodify(t.filename, ':t'), t.olp[#t.olp])
    end,
  })
  if choice then
    -- the picker only offers level-1 headlines, so its path ends there
    dest = { file = choice.filename, olp = { choice.olp[#choice.olp] } }
  end
  return dest
end

--- Template `target`: pick the destination, aborting the capture on cancel.
function M.target()
  if not M.pick() then
    require('org.utils').abort()
  end
  return dest and dest.file
end

--- Template `olp`: the outline path the destination picked by `target` names.
function M.olp()
  return dest and dest.olp
end

--- Capture a new entry under a known headline, in the headline's own file:
--- the Task template of the config, `target` and `olp` set to that entry.
--- The outline path must name the entry itself, not just its ancestors --
--- `Headline:outline_path` returns the ancestors only -- and resolving to an
--- ancestor would file the entry beside the entry at point, at the top level
--- as a sibling for a level-1 entry (where the empty path fails outright).
--- Both capture-under-entry ways in go through here: `c` / <leader>aC in a
--- TODO view (helpers/org/tree.lua, the agenda item's headline) and `c` on a
--- headline in an org file (helpers/org/mappings.lua).
---@param hl org.Headline|nil the entry to capture into
---@param filename string|nil the file the entry lives in
function M.under(hl, filename)
  if not (hl and filename) then
    require('org.utils').warn 'org: no entry under the cursor'
    return
  end
  local tpl = vim.deepcopy(require('org.config').opts.capture.templates.t)
  tpl.target = filename
  local olp = hl:outline_path()
  olp[#olp + 1] = hl:plain_title()
  tpl.olp = olp
  require('org.capture').capture(tpl)
end

--- The language a `#+begin_src` block of `buf` opens with: its filetype,
--- with the names org spells differently. A buffer whose filetype is plain
--- `text` opens a block with no language at all.
---@param buf integer
---@return string
local function src_lang(buf)
  local names = {
    bash = 'sh',
    cs = 'csharp',
    javascriptreact = 'jsx',
    text = '',
    typescriptreact = 'tsx',
    zsh = 'sh',
  }
  local ft = vim.bo[buf].filetype
  if names[ft] ~= nil then
    return names[ft]
  end
  return ft
end

--- The Visual selection as the capture's starting content: its lines in a
--- `#+begin_src` block of the origin buffer's language, at column 0 -- the
--- template's `  %i` indents every line with the lead the escape is spelled
--- with. Empty when the capture was not started on a selection, so a
--- template carries `%i` either way and shows nothing without one.
---@return string
function M.selection()
  local mode = vim.fn.mode()
  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then
    return ''
  end
  local utils = require 'org.utils'
  local buf = vim.api.nvim_get_current_buf()
  local srow, scol, erow, ecol = utils.visual_range()
  utils.exit_visual()
  local lines = vim.api.nvim_buf_get_lines(buf, srow - 1, erow, false)
  if mode == 'v' and #lines > 0 then
    lines[#lines] = lines[#lines]:sub(1, ecol)
    lines[1] = lines[1]:sub(scol)
  end
  local lang = src_lang(buf)
  local out = { '#+begin_src' .. (lang ~= '' and (' ' .. lang) or '') }
  vim.list_extend(out, lines)
  out[#out + 1] = '#+end_src'
  return table.concat(out, '\n')
end

--- The template text that carries the Visual selection: the `%i` line the
--- templates append when the capture was started on a selection
--- (`M.selection`), empty otherwise. `%i` repeats the lead it is spelled
--- with on every line of the block, so the block is indented like the entry
--- body around it.
---@param ctx table
---@return string
function M.block(ctx)
  if not (ctx and ctx.initial and ctx.initial ~= '') then
    return ''
  end
  return '\n  %i'
end

--- Capture with the Task template (`t`) from Visual mode: `^` there, the
--- selection carried in as a source block (the template's `%i`), the entry
--- filed at a project's headline as usual.
function M.task()
  local initial = M.selection()
  require('org.utils').run(function()
    require('org.capture').capture('t', { initial = initial })
  end)
end

--- The destination of the roam capture, picked once per capture: the file
--- the note goes to, and the line of the headline it is filed under (nil
--- for the file itself, whose entries go at its end).
local roam_dest

--- Every place a note can be filed into: each file of the knowledge base,
--- and every headline under it, level by level with its outline path. The
--- list is the files, not the roam index: a node needs an `:ID:` on its
--- headline, and a base written by hand or by an agent has few, so an
--- index-only finder would offer the files and almost nothing inside them.
--- A capture target needs no `:ID:` -- it is a line of a file.
---@return { name: string, file: string, rel: string, lnum?: integer, olp: string[] }[]
local function roam_candidates()
  local db = require 'org.extensions.roam.db'
  local out = {}
  local function walk(path, rel, hl, parents)
    local title = hl:plain_title()
    local here = parents
    if title and title ~= '' and not hl.inlinetask then
      here = vim.list_extend(vim.deepcopy(parents), { title })
      out[#out + 1] = { name = title, file = path, rel = rel, lnum = hl.line, olp = here }
    end
    for _, child in ipairs(hl.children or {}) do
      walk(path, rel, child, here)
    end
  end
  for _, path in ipairs(db.list_files()) do
    local rel = db.relative(path) or vim.fn.fnamemodify(path, ':t')
    local file = require('org.files').get(path)
    local title = vim.trim((file.settings and file.settings.title) or '')
    out[#out + 1] = { name = title ~= '' and title or vim.fn.fnamemodify(path, ':t:r'), file = path, rel = rel, olp = {} }
    -- the top-level headlines carry the rest as children; a flat list of
    -- every headline would walk the subtrees twice
    for _, hl in ipairs(file.headlines) do
      if (hl.level or 1) == 1 then
        walk(path, rel, hl, {})
      end
    end
  end
  return out
end

--- Ask the picker for the destination: every file and headline of the
--- knowledge base, searched fuzzily by title, each with the file (and the
--- outline path) it lives in beside it. Aborts the capture when the picker
--- is cancelled or answers nothing.
---@return table|nil
local function roam_pick()
  local utils = require 'org.utils'
  local items = {}
  for _, c in ipairs(roam_candidates()) do
    local where = c.rel .. (#c.olp > 0 and (' › ' .. table.concat(c.olp, ' › ')) or '')
    items[#items + 1] = {
      display = { { c.name, 'Title' }, { '  ' .. where, 'Comment' } },
      text = c.name .. ' ' .. where,
      filename = c.file,
      lnum = c.lnum,
      value = c,
    }
  end
  local choice = require('org.pickers').choose { title = 'Refile to', items = items }
  if not (choice and choice[1]) then
    utils.abort()
  end
  local picked = choice[1].value
  roam_dest = { file = picked.file, lnum = picked.lnum }
  return roam_dest
end

--- The picked destination as a place: its buffer, and the line of the
--- headline to file under -- nil for a file, whose entries go at the end of
--- it. The picker runs here, once per capture.
---@return table { buf: integer, lnum: integer|nil }
local function roam_dest_at()
  local dest = roam_dest or roam_pick()
  return { buf = require('org.utils').load_buffer(dest.file), lnum = dest.lnum }
end

--- Template `location` of the roam template (`r`): the buffer and line the
--- entry goes to. A headline picked in the finder files the entry under it,
--- as a child; a file files it at the end, beside the last top-level entry.
--- The place is picked here, when the capture starts, so a capture
--- cancelled in the finder never opens a buffer.
---@return integer|nil bufnr
---@return integer|nil lnum
function M.roam_location()
  local dest = roam_dest_at()
  return dest.buf, dest.lnum or vim.api.nvim_buf_line_count(dest.buf)
end

--- Take the TODO keyword off the headline at `lnum` of `buf`, keeping its
--- level, priority and tags: a note filed into the knowledge base is not a
--- ticket, and the keyword is the one thing the capture template wrote that
--- does not belong there.
---@param buf integer
---@param lnum integer
local function strip_keyword(buf, lnum)
  local file = require('org.files').get_buffer(buf)
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
  local p = line and require('org.parser').parse_headline_line(line, file.settings and file.settings.todo)
  if not (p and p.todo) then
    return
  end
  p.todo = nil
  vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { require('org.edit').build_headline(p) })
end

--- Store the capture open in `buf` and refile the entry it stored into a
--- node of the knowledge base: `<C-c><C-n>` in a capture buffer, the other
--- way into the base the roam capture has. The node is picked first, so a
--- picker cancelled there leaves the capture open with its text; then the
--- entry is stored where the template files it, moved under the node -- or
--- to the end of its file -- and the TODO keyword comes off its headline,
--- since a note is not a ticket. The `%a` link the template wrote stays, so
--- the note still says where it came from. Nothing starts an omp run on it.
---@param buf integer
function M.roam_refile(buf)
  roam_dest = nil
  require('org.utils').run(function()
    local utils = require 'org.utils'
    local dest = roam_dest_at()
    local ok, dbuf, dline = pcall(require('org.capture').finalize, buf, { jump = false })
    if not (ok and dbuf and dline) then
      utils.warn 'org: the capture was not stored'
      return
    end
    local moved, b, l = pcall(require('org.refile').move, { bufnr = dbuf, lnum = dline }, { bufnr = dest.buf, lnum = dest.lnum })
    if not moved then
      utils.warn('org: the entry was not refiled: ' .. tostring(b))
      return
    end
    strip_keyword(b, l)
    utils.save_buffer_or_warn(dbuf)
    utils.save_buffer_or_warn(b)
    utils.notify('org: refiled into ' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ':~'))
  end)
end

--- Capture into the knowledge base: the `r` template of the config on
--- `<C-c><C-n>`, the entry a plain headline (no TODO keyword) under the node
--- the roam finder answers, linked back to where it came from (`%a`) and
--- carrying the Visual selection as a source block when there is one.
--- Nothing is started on the stored entry -- the run is the Task template's
--- alone (helpers/org/mappings.lua).
function M.roam()
  roam_dest = nil
  local initial = M.selection()
  require('org.utils').run(function()
    require('org.capture').capture('r', { initial = initial })
  end)
end

--- The date header line of a captured entry: `[<timestamp>] <rule>`.
---@param lines string[]
---@return integer|nil index in `lines`
local function header_line(lines)
  for i, l in ipairs(lines) do
    if l:match '^%s*%[[%d%-]+%s+%a%a%a[^%]]*%] %-+%s*$' then
      return i
    end
  end
end

--- Reorder `lines` so the entry's date header sits directly under the
--- headline -- title, header, description -- with the description (the lines
--- typed under the title in the capture buffer) indented like the header.
--- The template's `%?` sits on the headline, so a line typed below the title
--- lands *between* the headline and the date header, pushing the header one
--- line down; a captured entry should instead open its chronological log the
--- same way a note does. The template's `%a` is its last line, so the
--- annotation link back to the origin (org.nvim.lua, the `t` template) keeps
--- following the description. Returns the reordered lines and the header's
--- index **in the input**, or nil when there is nothing to move.
---@param lines string[]
---@return string[]|nil, integer|nil
local function reorder(lines)
  local at = header_line(lines)
  if not at or at <= 2 then
    return nil, at
  end
  local indent = lines[at]:match '^(%s*)'
  local out = { lines[1], lines[at] }
  for i = 2, #lines do
    if i ~= at then
      local l = lines[i]
      out[#out + 1] = l:match '^%S' and (indent .. l) or l
    end
  end
  return out, at
end

--- org.nvim store filter for the Task template: the same reorder, once, at
--- store time, so the placed entry reads title, header, description (and the
--- `%a` annotation last) even when the capture buffer was not kept in order
--- (a multi-line paste that the hook missed, say). When the header is already
--- first, any body line left at
--- column 0 (a description typed before the header, or pasted) is still
--- indented like the header. The timestamp is the one the capture buffer
--- carries (`%U`, the capture time), so the header is only moved, never
--- re-stamped.
---@param tpl table
---@param lines string[]
---@return string[]|nil
function M.header_first(tpl, lines)
  if tpl.key ~= 't' then
    return nil
  end
  local out = reorder(lines)
  if out then
    return out
  end
  local at = header_line(lines)
  if not at then
    return nil
  end
  local indent = lines[at]:match '^(%s*)'
  local changed = false
  local res = {}
  for i, l in ipairs(lines) do
    if i > 1 and i ~= at and l:match '^%S' then
      l = indent .. l
      changed = true
    end
    res[i] = l
  end
  return changed and res or nil
end

--- The tags the destination hands down to a captured entry: the target
--- headline's whole set -- its file's `#+FILETAGS:`, its ancestors' tags, its
--- own (org tag inheritance) -- or, for a capture landing at file level
--- (no target headline), the file's `#+FILETAGS:` alone. Empty when the
--- destination is unknown or claims none.
---@param ctx table
---@return string[]
local function inherited_tags(ctx)
  local file = ctx.target_file
  if not file then
    return {}
  end
  if ctx.target_hl then
    return ctx.target_hl:get_tags()
  end
  return vim.deepcopy(file.settings and file.settings.filetags or {})
end

--- Index of the captured entry's headline (its first `*` line) in `lines`.
---@param lines string[]
---@return integer|nil
local function headline_line(lines)
  local parser = require 'org.parser'
  for i, l in ipairs(lines) do
    if parser.headline_level(l) then
      return i
    end
  end
end

--- Append `tags` to the captured entry's headline in `lines`, once each and
--- in the order given, realigned like org-align-tags
--- (`org.edit.build_headline`). `file` is the destination, whose TODO
--- sequence the headline line is parsed with. Returns the new lines, or nil
--- when the entry carries no headline line, `tags` is empty, or every tag is
--- already there.
---@param lines string[]
---@param file? table
---@param tags string[]
---@return string[]|nil
function M.add_tags(lines, file, tags)
  if #tags == 0 then
    return nil
  end
  local at = headline_line(lines)
  if not at then
    return nil
  end
  local parser = require 'org.parser'
  local p = parser.parse_headline_line(lines[at], file and file.settings and file.settings.todo)
  if not p then
    return nil
  end
  local have, own = {}, {}
  for _, t in ipairs(p.tags) do
    have[t] = true
    own[#own + 1] = t
  end
  local added = false
  for _, t in ipairs(tags) do
    if not have[t] then
      have[t] = true
      own[#own + 1] = t
      added = true
    end
  end
  if not added then
    return nil
  end
  p.tags = own
  local out = vim.deepcopy(lines)
  out[at] = require('org.edit').build_headline(p)
  return out
end

--- org.nvim store filter: append the tags the destination inherits (see
--- `inherited_tags`) to the captured entry's headline, so a capture under
--- `allitude` lands `:allitude:pms:` instead of bare even though the agenda
--- would have shown it those tags anyway. Entry captures only. Returns nil
--- when nothing changed.
---@param tpl table
---@param lines string[]
---@param ctx table
---@return string[]|nil
function M.capture_tags(tpl, lines, ctx)
  if (tpl.type or 'entry') ~= 'entry' then
    return nil
  end
  ctx = ctx or {}
  return M.add_tags(lines, ctx.target_file, inherited_tags(ctx))
end

--- Whether the Task template keeps the stock `%a` line, the link back to the
--- entry the capture was started from: it names a place, and only a capture
--- started in a file has one. Anywhere else -- the TODO view, another view,
--- a terminal, a scratch buffer -- the link would just carry the text of the
--- node at point into an entry that lands in that same board, so the
--- template leaves the line out and no phrase shows in the capture buffer. A
--- link an org-protocol capture stored for itself (`link_store_props`, which
--- builds no origin context at all) is a place too, and is kept.
---@param ctx table
---@return boolean
function M.origin_link(ctx)
  if not (ctx and ctx.annotation) then
    return false
  end
  if ctx.origin_buf == nil then
    return true
  end
  return ctx.origin_file ~= nil and ctx.origin_file ~= ''
end

--- Template `hook`: keep the capture buffer itself in that order as the entry
--- is typed. Without it the header sits below the description while the
--- capture is open -- the cursor types *above* the date line -- and only the
--- store filter fixes the entry afterwards; with it, the Enter that starts a
--- description moves the header back under the title, so the description (and
--- the cursor) land below the header, where they belong, and the buffer reads
--- the way the stored entry will. The reorder runs on the first edit that
--- pushes the header down and is a no-op every other time.
---@param buf integer
function M.hook(buf)
  local busy = false
  local function keep()
    if busy or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local win = vim.fn.bufwinid(buf)
    local cursor = win ~= -1 and vim.api.nvim_win_get_cursor(win) or nil
    local out, at = reorder(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    if not out then
      return
    end
    busy = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
    if cursor then
      -- the lines above the header shift down one; the header goes to 2
      local row = cursor[1]
      if row < at then
        row = row + 1
      elseif row == at then
        row = 2
      end
      pcall(vim.api.nvim_win_set_cursor, win, { math.min(row, #out), cursor[2] })
    end
    busy = false
  end
  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, { buffer = buf, callback = keep })
end

function M.setup()
  require('org.lazy').on_load('org.capture', 'helper_capture', function(capture)
    capture.store_filters.capture_header = M.header_first
    capture.store_filters.capture_tags = M.capture_tags
    capture.store_filters.capture_autotags = require('helpers.org.autotags').filter
  end)
end

return M
