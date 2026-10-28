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
--              something writes the file once more. `no_prompt` is its
--              second half, for a caller that cannot answer: see below.
--
-- When the file moved on since the read (an agent wrote after nvim read, so
-- the buffer's own edits sit on an older text), the write is left to nvim: the
-- prompt is the honest answer there, the one place a human has to choose a
-- version. It cannot happen for the writes above -- the watcher refreshes the
-- buffers of the whole tree on every org write -- only for a buffer whose
-- text was already stale when the view edited it.
--
-- A caller with no human at the prompt must ask `M.stale` instead: the
-- launcher (helpers/org/ai.lua) runs from a mapping and from the
-- `nvim --headless` climb, where the unforced `:write` is a W12 question
-- nothing answers -- the step hangs rather than failing -- and a forced one
-- drops the other writer's text. It reloads what it can and refuses the
-- launch on a stale buffer. The check and the write are two steps, though --
-- the launcher writes the drawer and the claim into the buffer in between,
-- and another writer can land in that window -- so the write it makes is
-- `no_prompt` (`M.save`): a write it cannot prove safe is refused, the
-- launch aborts, and the question is never put to a nvim that would wait on
-- it (the mapping froze there, the headless climb had nobody to type for it).
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

--- The org files nvim wrote itself, by normalized path, with the loop time of
--- the write: the watcher's event for one of them is nvim's own save, not news
--- from another process. helpers/org/alerts.lua reads the mark (M.wrote) to
--- keep from announcing a state the user just changed in a view back to them.
---@type table<string, integer>
local wrote = {}

--- How long a mark stands for: the burst it belongs to (the watcher debounces
--- at 120 ms) and no longer, so a stale mark cannot swallow a real write.
local MARK_MS = 2000

--- Whether nvim wrote `path` within the current burst, the mark cleared on the
--- way out: one save is one event.
---@param path string
---@return boolean
function M.wrote(path)
  local key = vim.fs.normalize(path)
  local at = wrote[key]
  wrote[key] = nil
  return at ~= nil and vim.uv.now() - at < MARK_MS
end

---@param path string
local function mark_wrote(path)
  wrote[vim.fs.normalize(path)] = vim.uv.now()
end

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

--- Whether the file moved on since the text `bufnr` holds was read -- the
--- buffer's edits sit on a version the file has left behind, so writing it
--- back would drop whatever the other writer put there.
---
--- A buffer whose text is the file's is reloaded first (M.refresh), which
--- makes it current: only a buffer nvim holds edits in can be stale, and the
--- answer then is the module's own record of the read (`reads`), the one the
--- watcher keeps up to date. A buffer the module never recorded is not
--- called stale: nvim's own check answers for it, as it does for a `:write`
--- made from the keyboard.
---
--- The callers that may not prompt -- the launcher of
--- `helpers/org/ai.lua`, run from a mapping and from a `nvim --headless`
--- climb -- ask this before they write: an unforced `:write` there is the
--- W12 question, which nothing answers, so the write hangs instead of
--- failing. A human's `:w` still gets the question (`M.save`).
---@param bufnr integer
---@return boolean
function M.stale(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if not vim.bo[bufnr].modified then
    M.refresh(bufnr)
  end
  if not vim.bo[bufnr].modified then
    return false
  end
  local rec = reads[bufnr]
  if not rec then
    return false
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  return path ~= '' and stat_key(path) ~= rec
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
---
--- `opts.no_prompt` is the caller's word that it cannot answer the W12
--- question: a write it cannot prove safe -- the file is not the one the
--- buffer was read from (`M.fresh`) and the buffer's text is not the file's
--- (`content_equal`) -- is refused instead of asked, so the caller aborts
--- with a reason instead of a nvim waiting on an answer nobody types. The
--- launcher of helpers/org/ai.lua is that caller (see the module comment).
---@param bufnr integer
---@param opts? { no_prompt: boolean }
---@return boolean ok, string? err
function M.save(bufnr, opts)
  if not (vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].modified and vim.api.nvim_buf_get_name(bufnr) ~= '') then
    return true
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local force = M.fresh(bufnr) or content_equal(bufnr, path)
  if not force and opts and opts.no_prompt then
    return false, 'the file changed since the buffer was read'
  end
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
    mark_wrote(path)
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
      mark_wrote(vim.api.nvim_buf_get_name(ev.buf))
      M.remember(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufReadPost', {
    pattern = { '*.org', '*.org_archive' },
    callback = function(ev)
      M.remember(ev.buf)
    end,
  })
  -- The org file a session starts on is read before these hooks exist: its
  -- BufReadPost runs, then FileType, and only then does org.nvim -- and so
  -- this module -- load. Its text is the file's, so the stat now is the one
  -- it was read at: record it, or the freshness proof (`M.fresh`) the writes
  -- are made on would fail on it and refuse a launch it should allow.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == '' and (name:match '%.org$' or name:match '%.org_archive$') then
      M.remember(buf)
    end
  end
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
