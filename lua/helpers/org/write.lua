-- Writing an org file that something else rewrote under nvim.
--
-- An org file in this vault has more than one writer: an `omp` run writes its
-- ticket back (helpers/org/ai.lua, helpers/org/watch.lua), and the wiki is
-- edited from other sessions at the same time. nvim remembers the file it read
-- (its mtime), and when the file changed since, `:write` asks "Do you really
-- want to write to it (y/n)?" -- a question a todo view cannot answer, since
-- its writes (a state change, a note, a launched ticket) are made by the view,
-- not by a human at the prompt. The watcher reloads the changed text into the
-- buffer in place, which is what makes the view show the write-back; the
-- question then comes from nvim's bookkeeping of the file, which that reload
-- cannot update (`:checktime` and `:edit` are the only ways, and on a buffer no
-- window shows both open a temporary window and flash it over the view).
--
-- So the write side answers it instead, in the two halves:
--
--   M.refresh  reload the buffer's text in place from disk -- no window, no
--              autocmds, the reload the watcher already runs -- and record the
--              file's stat this text was read at. That record, not nvim's
--              internal one, is what the write can see.
--
--   M.save     write the buffer the way org.utils.save_buffer does, but with
--              `:write!` when the file's stat is still the recorded one: the
--              file has not been touched since nvim read the text the buffer
--              carries, so nothing an unforced write would have preserved can
--              be lost -- and the write itself re-syncs nvim's bookkeeping
--              (ml_timestamp), so the buffer is not asked about again until
--              something writes the file once more.
--
-- When the file moved on since the read (an agent wrote after nvim read, so
-- the buffer's own edits sit on an older text), the write is left to nvim: the
-- prompt is the honest answer there, the one place a human has to choose a
-- version. It cannot happen for the writes above -- the watcher refreshes the
-- buffers of the whole tree on every org write -- only for a buffer whose
-- text was already stale when the view edited it.
--
-- M.setup() replaces `require('org.utils').save_buffer` with M.save: org's own
-- view actions (a state change, a note, a checkbox, a refile) all write
-- through it, so that is the one place the question comes from. The config's
-- own writes (helpers/org/ai.lua's launcher, helpers/org/agenda.lua's entry
-- scratch) call M.save directly.
local M = {}

--- The stat the text of every buffer we read was read at, as
--- `"<sec>.<nsec>:<size>"`, keyed by buffer number: nvim keeps its own copy of
--- this and does not hand it out, so the module keeps the one it needs.
---@type table<integer, string>
local reads = {}

--- The stat of `path` as a comparable string, or nil when it is not there.
---@param path string
---@return string|nil
local function stat_key(path)
  local st = vim.uv.fs_stat(path)
  if not st then
    return nil
  end
  return ('%d.%d:%d'):format(st.mtime.sec, st.mtime.nsec, st.size)
end

--- Remember the file a buffer's text now matches -- run after every read the
--- module makes and after every write nvim itself makes (a BufWritePost), so
--- the record is "the content the buffer holds is this version of the file". A
--- modified buffer keeps its record: its edits sit on the text read at that
--- stat, which is exactly what M.save has to compare against.
---@param bufnr integer
function M.remember(bufnr)
  if vim.bo[bufnr].modified then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path ~= '' then
    reads[bufnr] = stat_key(path)
  end
end

--- Whether the file is still the one whose text the buffer was read from: the
--- only proof a write may be forced on.
---@param bufnr integer
---@return boolean
function M.fresh(bufnr)
  local rec = reads[bufnr]
  if not rec then
    return false
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  return path ~= '' and stat_key(path) == rec
end

--- Whether the buffer's text is what the file holds, so writing it back
--- changes nothing but the mtime.
---@param bufnr integer
---@param path string
---@return boolean
local function content_equal(bufnr, path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return false
  end
  if #lines == 0 then
    lines = { '' }
  end
  local tail_ok, tail = pcall(vim.fn.readblob, path, -1, 1)
  if not tail_ok or vim.bo[bufnr].eol ~= (tail == '\n') then
    return false
  end
  return vim.deep_equal(lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
end

--- Reload a buffer from disk, in place, without showing it.
---
--- `nvim_buf_call` on a buffer no window shows opens a temporary window at the
--- top left (aucmd_prepbuf) to run the autocmds in; a redraw inside it paints
--- that buffer over the view. The watcher runs on every org write -- the view
--- feeds it -- and reloads every loaded org file, so every save flashed the
--- file behind the one being edited (and a `:checktime` did the same). The text
--- is swapped in place instead: org.files keys its parse on the changedtick, so
--- the next render sees it.
---
--- A buffer with unsaved edits is left alone, as `:checktime` does; an encoding
--- or fileformat the plain read cannot reproduce is left for the next time the
--- buffer is shown ('autoread' reloads it there, in its own window).
---@param bufnr integer
---@return boolean reloaded
function M.refresh(bufnr)
  if vim.bo[bufnr].modified then
    return false
  end
  local enc = vim.bo[bufnr].fileencoding
  if enc ~= '' and not enc:lower():match '^utf%-8' then
    return false
  end
  if vim.bo[bufnr].fileformat ~= 'unix' and vim.bo[bufnr].fileformat ~= 'dos' then
    return false
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  -- the stat first: a write landing between it and the read leaves the record
  -- older than the text, so a later save falls back to nvim's own check
  -- instead of forcing a write over a version it never saw
  local before = stat_key(name)
  local ok, lines = pcall(vim.fn.readfile, name)
  if not ok then
    return false
  end
  reads[bufnr] = before
  if #lines == 0 then
    lines = { '' }
  end
  local tail_ok, tail = pcall(vim.fn.readblob, name, -1, 1)
  if vim.deep_equal(lines, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) then
    return false
  end
  -- an external reload is not an undo step
  local saved = vim.bo[bufnr].undolevels
  vim.bo[bufnr].undolevels = -1
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].undolevels = saved
  -- :edit keeps a file without a final newline as such ('eol' off)
  if tail_ok then
    vim.bo[bufnr].eol = tail == '\n'
  end
  -- nvim_buf_set_lines marks the buffer modified; the text is the file's
  vim.bo[bufnr].modified = false
  return true
end

--- Write a buffer silently if it has changes, the way org.utils.save_buffer
--- does -- `org.write_hooks` around the write, an unmodified or unnamed buffer
--- skipped, `org.files`' disk cache invalidated after -- but forced when the
--- file is still the one the buffer was read from (see the module comment).
--- Returns false and a one-line error when the write fails.
---@return boolean ok, string? err
function M.save(bufnr)
  if not (vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified and vim.api.nvim_buf_get_name(bufnr) ~= '') then
    return true
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local force = M.fresh(bufnr) or content_equal(bufnr, path)
  local hooks = require 'org.write_hooks'
  local hok, herr, run = hooks.run_pre(bufnr, 'save_buffer')
  if not hok then
    return false, herr
  end
  local ok, err
  vim.api.nvim_buf_call(bufnr, function()
    ok, err = pcall(vim.cmd, force and 'silent noautocmd keepalt write!' or 'silent noautocmd keepalt write')
  end)
  if ok then
    require('org.files').invalidate(path)
    M.remember(bufnr)
  end
  hooks.run_post(run, ok)
  if not ok then
    err = tostring(err)
    return false, err:match 'E%d+:[^\n]*' or err:match '^[^\n]*'
  end
  return true
end

--- Take over org's own background write, and follow nvim's writes of org
--- files (a `:w` of the user, an `:edit`-reload) so the record stays the file
--- the buffer's text matches.
function M.setup()
  vim.api.nvim_create_autocmd('BufWritePost', {
    pattern = { '*.org', '*.org_archive' },
    callback = function(ev)
      M.remember(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    callback = function(ev)
      reads[ev.buf] = nil
    end,
  })
  require('org.lazy').on_load('org.utils', 'helper_write', function(utils)
    utils.save_buffer = M.save
  end)
end

return M
