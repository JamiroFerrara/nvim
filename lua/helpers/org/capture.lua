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
-- the captured entry's headline. A project file carrying `#+FILETAGS:
-- allitude` and a `PMS` headline tagged `:pms:` therefore captures
-- `:allitude:pms:`, the same set the agenda would have shown the entry anyway
-- through org tag inheritance; the tags are written, not merely inherited.
-- Both capture paths that reach this store (the `^` Task capture and the
-- `c` / <leader>aC capture-under-entry of helpers/org/tree.lua) go through
-- the filter, so the setting covers either way in.
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
--- same way a note does. Returns the reordered lines and the header's index
--- **in the input**, or nil when there is nothing to move.
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
--- store time, so the placed entry reads title, header, description even when
--- the capture buffer was not kept in order (a multi-line paste that the hook
--- missed, say). When the header is already first, any body line left at
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
  end)
end

return M
