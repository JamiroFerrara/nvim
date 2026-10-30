-- One entry on its own: an `org-entry://` scratch holding the entry's own
-- lines -- its headline through the end of its subtree -- written back into
-- its file in place of the entry. `<CR>` in the agenda opens one
-- (helpers/org/agenda.lua), and so does following a link that names a single
-- entry -- an `id:` link, or a `file:` link into an org file with a line, a
-- headline or a custom id after `::` -- since reading one ticket never needs
-- the rest of the board around it. `setup` wraps `org.links.open`, the one
-- call every door that follows a link goes through (<CR>, `gx`, a mouse
-- click, the context menu, `:OrgOpen`), so a link that lands on an entry
-- opens the entry and no other door needs to know about it.
--
-- The buffer is a scratch: acwrite (so `:w` runs the write hook below instead
-- of touching a file), wiped when left, `q` puts the buffer it came from back
-- (`buffer #`). It takes the entry's own lines from its file, so it shows
-- what the file holds now, unsaved edits included. It is editable: `:w`
-- splices the buffer back into its file in place of the entry and writes it.
-- The entry's start is marked with an extmark in the source buffer, so a
-- write after edits elsewhere in the file still lands on the entry; the
-- subtree range is recomputed at the mark each time. The window wraps by
-- default, its previous wrap value restored when the scratch goes. Leaving
-- the scratch never asks to save it (nothing about it looks unsaved to nvim,
-- see the guard below) and keeps the edits: the buffer is written back on the
-- way out as well as on `:w`, so `q` and every buffer command answer nvim's
-- "Save changes to ...?" with yes instead of raising it.
local M = {}

--- The namespace of the marks left on the entries the scratches copy: shared
--- by name with helpers/org/ai.lua, which reads the pair back to act on the
--- real headline behind a preview.
local NS = vim.api.nvim_create_namespace 'org_entry_scratch'

--- The buffer holding `path`, loaded without showing it. An entry's source is
--- read from its buffer (unsaved edits included), so a file no window shows
--- is loaded first -- a link can name a ticket in a board that was never
--- open.
---@param path string
---@return integer
local function load(path)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  return buf
end

--- Open the entry that begins at `line` of buffer `src` in an
--- `org-entry://` scratch, in `opts.win` when given (the current window
--- otherwise), with the cursor on `opts.cursor` (a line of `src`, for a
--- link whose search lands inside the entry).
---@param src integer the buffer holding the entry
---@param line integer 1-based line of the entry's headline
---@param opts? { win?: integer, cursor?: integer }
---@return integer|nil buf
function M.open(src, line, opts)
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(src) then
    return nil
  end
  local hl = require('org.files').get_buffer(src):headline_at(line)
  if not hl then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(src, hl.line - 1, hl.end_line, false)
  local span = hl.end_line - hl.line + 1
  local mark = vim.api.nvim_buf_set_extmark(src, NS, hl.line - 1, 0, { right_gravity = false })

  local win = opts.win or vim.api.nvim_get_current_win()
  local prev_wrap = vim.wo[win].wrap
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local base = (hl.title and hl.title ~= '' and hl.title or 'entry'):gsub('[%s/\\]', '_')
  -- A scratch of the same entry -- or of one sharing its title -- can still
  -- be alive when this one is built: the `L` pane rebuilds its scratch when
  -- the entry it holds changes under it (helpers/org/agenda.lua). nvim
  -- refuses to give two buffers one name, so take the first free one rather
  -- than leave the new scratch unnamed (its name is how the pane and `:ls`
  -- tell it apart).
  local name = 'org-entry://' .. base
  local n = 1
  local function taken(nm)
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(b) == nm then
        return true
      end
    end
    return false
  end
  while taken(name) do
    n = n + 1
    name = 'org-entry://' .. base .. '#' .. n
  end
  pcall(vim.api.nvim_buf_set_name, buf, name)
  -- Remember where the copy came from. The buffer is a preview of one source
  -- entry, so entry commands that read the buffer under the cursor
  -- (helpers/org/ai.lua's <leader>ai) must resolve to `src` -- and to the
  -- entry's first line, kept by the extmark as the file is edited -- instead
  -- of treating the scratch's `org-entry://` name as a file. Write_back reads
  -- the same pair.
  vim.b[buf].org_entry_source = src
  vim.b[buf].org_entry_mark = mark
  -- Show the buffer before it becomes an org buffer: the FileType hooks
  -- (org.nvim's buffer setup, helpers/org/mappings.lua) reach for the buffer
  -- with nvim_buf_call, and on a buffer no window shows that call opens a
  -- temporary window at the top left (aucmd_prepbuf), which a redraw in the
  -- hook then paints over the view -- a flash the preview pane, which builds
  -- one scratch per entry, would show on every move.
  vim.api.nvim_win_set_buf(win, buf)
  vim.bo[buf].filetype = 'org'
  vim.wo[win].wrap = true
  local cursor = opts.cursor and (opts.cursor - hl.line + 1) or nil
  if cursor and cursor > 0 and cursor <= span then
    vim.api.nvim_win_set_cursor(win, { cursor, 0 })
  end
  -- The preview is a scratch holding a copy of the entry; it is written back
  -- into the source file in place of the entry (the extmark keeps the
  -- position across edits elsewhere in the file).
  local dirty = false
  local function write_back()
    if not vim.api.nvim_buf_is_valid(src) or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local pos = vim.api.nvim_buf_get_extmark_by_id(src, NS, mark, {})
    local at = (pos[1] or (hl.line - 1)) + 1
    local cur = require('org.files').get_buffer(src):headline_at(at)
    local from = cur and cur.line or at
    local to = cur and cur.end_line or (from + span - 1)
    vim.api.nvim_buf_set_lines(src, from - 1, to, false, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    vim.api.nvim_buf_set_extmark(src, NS, from - 1, 0, { id = mark, right_gravity = false })
    if vim.api.nvim_buf_get_name(src) ~= '' then
      require('helpers.org.write').save(src)
    end
    dirty = false
    vim.b[buf].org_entry_dirty = nil
  end

  -- nvim must never believe the preview holds unsaved work. With `confirm` on
  -- it checks the modified flag for every command that drops a buffer --
  -- `:bdelete`, `:bwipeout`, `:edit`, `:enew`, `:close` -- before any buffer
  -- autocommand fires, so clearing it in QuitPre (which only covers `:q` /
  -- `:wq` / `:qa`) left the rest asking "Save changes to ...?". The flag is
  -- dropped again after every change and the buffer is tracked as `dirty`
  -- instead: the answer to that question is always yes -- `:w` and leaving
  -- the preview both write the edits back (write_back), so nothing is lost
  -- and the prompt cannot come back. `:w` still runs the write hook
  -- (BufWriteCmd fires on an unmodified acwrite buffer). `dirty` is kept on
  -- the buffer as well (`org_entry_dirty`), because the preview pane
  -- (helpers/org/agenda.lua) replaces the buffer under its caller's feet: a
  -- buffer swapped out from inside an autocommand is wiped without its
  -- BufHidden / BufWipeout running, so the pane writes the edits back itself
  -- before the swap instead of leaving it to the handlers below.
  local function unmodify()
    dirty = true
    vim.b[buf].org_entry_dirty = true
    vim.bo[buf].modified = false
  end
  vim.bo[buf].modified = false
  -- on_lines sees every change to the buffer, keystroke or API alike
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      unmodify()
    end,
  })
  vim.keymap.set('n', 'q', function()
    vim.cmd 'buffer! #'
  end, { buffer = buf, desc = 'org: close the entry view' })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      write_back()
      vim.bo[buf].modified = false
    end,
  })
  vim.api.nvim_create_autocmd({ 'QuitPre', 'BufHidden', 'BufWipeout' }, {
    buffer = buf,
    callback = function()
      -- leaving the preview is the other "yes": an edited preview is written
      -- back rather than dropped -- but only while it still holds the entry.
      -- `:edit` on the scratch reloads the (nonexistent) file and empties it,
      -- and writing that back would wipe the entry out of its file. QuitPre is
      -- here for `:q` on the last window, where the buffer never gets hidden
      -- (nvim exits first).
      local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      if dirty and first ~= nil and first:find '^%*+%s' then
        pcall(write_back)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.wo[win].wrap = prev_wrap
      end
      if vim.api.nvim_buf_is_valid(src) then
        pcall(vim.api.nvim_buf_del_extmark, src, NS, mark)
      end
    end,
  })
  return buf
end

--- An org file by its extension: the two org.nvim gives the org filetype.
---@param path string
---@return boolean
local function is_org_file(path)
  local ext = (path:match '%.([%w_]+)$' or ''):lower()
  return ext == 'org' or ext == 'org_archive'
end

--- The entry `target` names, as the buffer holding it, the line its headline
--- starts on, and the line to land on when the link searches inside it. nil
--- when the target is no single entry: another kind of link, a file link with
--- nothing after `::`, an entry in the buffer the link sits in (a jump there
--- costs nothing, and narrowing it would take the reader out of the file they
--- were reading), or a search that finds nothing.
---@param target string
---@param bufnr integer the buffer the link is followed from
---@return { src: integer, line: integer, cursor: integer }|nil
local function entry_at(target, bufnr)
  local links = require 'org.links'
  local link = links.read_target(target, bufnr)
  local path, search, loc
  if link.type == 'id' then
    local option
    loc, _, option = links.find_id_link(link.path)
    if not loc or not loc.filename then
      return nil
    end
    path, search = loc.filename, option
  elseif link.type == 'file' or link.type == 'file+emacs' or link.type == 'file+sys' then
    local p, s = link.path:match '^(.-)::(.*)$'
    if not p or vim.trim(s or '') == '' then
      return nil
    end
    path, search = links.file_link_path(p, bufnr), s
  else
    return nil
  end
  if not is_org_file(path) then
    return nil
  end
  local utils = require 'org.utils'
  if not utils.exists(path) then
    return nil
  end
  local src = utils.find_buffer(path) or load(path)
  if src == bufnr then
    return nil
  end
  local file = require('org.files').get_buffer(src)
  local lnum
  if not search then
    lnum = loc.lnum or 1
  elseif search:match '^%d+$' then
    lnum = tonumber(search)
  else
    -- an `id:` link's option searches inside its entry (org-id-open narrows
    -- to it first), a file link's in the whole file
    local range = loc and loc.headline and { loc.headline.line, loc.headline.end_line } or nil
    local lines = vim.api.nvim_buf_get_lines(src, 0, -1, false)
    local found = links.search_location(search, { lines = lines, file = file }, { range = range })
    if not found then
      return nil
    end
    lnum = found
  end
  local hl = file:headline_at(lnum)
  if not hl then
    return nil
  end
  return { src = src, line = hl.line, cursor = lnum }
end

--- Follow every link that names one entry into that entry's scratch, all the
--- doors at once: wrap `org.links.open`, which `open_at_point`, the mouse, the
--- context menu and `:OrgOpen` all go through, and hand everything else to it
--- untouched. A count keeps org.nvim's own meaning (an explicit "open the
--- file", another window, the system app), so it is passed through.
function M.setup()
  -- The link is answered only once org.nvim's own module is there to wrap, so
  -- a link costs nothing extra until one is followed for the first time.
  require('org.lazy').on_load('org.links', 'entry_links', function(links)
    local open = links.open
    links.open = function(target, opts)
      opts = opts or {}
      local arg = opts.arg or 0
      local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
      if arg == 0 then
        local ok, entry = pcall(entry_at, target, bufnr)
        if not ok then
          -- a link still opens: the entry is an optimization, and saying so
          -- beats a door that stops working on an unexpected link
          require('org.utils').warn('org-entry: ' .. tostring(entry))
        elseif entry and M.open(entry.src, entry.line, { cursor = entry.cursor }) then
          return true
        end
      end
      return open(target, opts)
    end
  end)
end

return M
