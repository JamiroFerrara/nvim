-- Agenda-side customizations for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): the `D` toggle_done action (and the
-- cursor it leaves on the line it acted on), the one-key tag/priority
-- toggles (helpers/org/tagging.lua), the fold state
-- left behind by entering an entry, the editable scratch view `<CR>` opens
-- with only that entry (wrapped by default, written back into its file on
-- save or when it is left) -- in a TODO view a checkbox line takes `<CR>`
-- for its own toggle instead (helpers/org/tree.lua) --, the `L` preview
-- pane that keeps that scratch
-- beside the view and reloads it as the cursor moves or the entry under it
-- changes (setup_entry_preview),
-- the insert mode a terminal window would
-- otherwise leave in the agenda, the re-render after a capture filed from
-- it (with the subtree range of a headline project's `°` view kept in step,
-- else the entry it just wrote falls outside it), the category column of
-- the entry lists -- its width measured off the entries a block shows, so
-- long project names do not push their own line's date, keyword and title
-- right of the neighbours (setup_category_width) --, the `§` / `°` launch keys
-- hiding the view they already opened (toggle_view), and the 1..3 switch
-- between the custom views of
-- agenda.custom_commands. All of them plug into modules
-- the plugin loads on first use, so they go through org.lazy.on_load and
-- nothing here is required at startup.
--
-- The agenda opens in the focused window (agenda.window = 'current' in the
-- plugin spec), so there is no split to unwrap on open and `q` puts the
-- previous buffer back (view/window.lua, mode "current").
local M = {}

-- `D` in the agenda toggles an entry between DONE and TODO: a done entry
-- goes back to TODO, anything else (open, or no keyword at all) becomes
-- DONE. change_state runs the full org semantics (CLOSED timestamp, state
-- logging, blockers, repeaters). The agenda mapping table only addresses
-- actions by name, so the action is added to the agenda action table
-- (org.agenda.view.actions); the `mappings.agenda.toggle_done = 'D'` in the
-- plugin spec points `D` at it. The hook runs inside `require
-- 'org.agenda.view'`, before view.open builds the agenda mappings from that
-- table.
--
-- `D` is pressed in runs, and the state change's write-back rebuilds the
-- view: the view saves the file (org.nvim's agenda.save_after_edit), the
-- tree watcher sees the save (helpers/org/watch.lua) and helpers/org/ai.lua
-- M.sync calls view.redo. redo keeps the cursor on the entry it was on, so it
-- follows the entry just marked -- into the board's Done section, or off a
-- list that filters done entries -- while the entries still to mark move out
-- from under the cursor. The action records the line it acted on and the redo
-- wrapper below puts the cursor back on that line, where the next entry has
-- moved up, so the next `D` hits it.
local stay

local function setup_toggle_done()
  require('org.lazy').on_load('org.agenda.view', 'toggle_done', function(view)
    view.actions.toggle_done = view.on_item(function(target)
      local win = view.state.win
      if win and vim.api.nvim_win_is_valid(win) then
        stay = { line = vim.api.nvim_win_get_cursor(win)[1], deadline = (vim.uv or vim.loop).now() + 1000 }
      end
      local bufnr, file, hl = require('org.edit').resolve_headline(target)
      if not bufnr then
        return
      end
      local done = file.settings.todo:is_done(hl.todo)
      return require('org.todo').change_state({ bufnr = bufnr, lnum = hl.line }, done and 'TODO' or 'DONE')
    end, 'lines')
  end)
end

-- Keep the cursor where it was for the rebuild a `D` causes (see
-- setup_toggle_done above): the wrapped redo restores the recorded line --
-- clamped when the view came out shorter -- in place of its own
-- follow-the-entry rule. The record covers only the rebuild the `D`'s own
-- save triggers, so it is dropped once used or once its window (the tree
-- watcher's debounce) is past. It also only applies while the cursor is
-- still on the line the `D` acted on: a cursor moved in the meantime (a `j`
-- between the `D` and the rebuild) is left to redo's follow rule. `N`
-- cycling a keyword, and a write-back from outside, keep that rule too.
local function setup_redo_stay()
  require('org.lazy').on_load('org.agenda.view', 'redo_stay', function(view)
    local redo = view.redo
    view.redo = function(...)
      local s = stay
      stay = nil
      local win = view.state.win
      local restore = s
        and (vim.uv or vim.loop).now() <= s.deadline
        and win
        and vim.api.nvim_win_is_valid(win)
        and vim.api.nvim_win_get_cursor(win)[1] == s.line
      redo(...)
      if restore and win and vim.api.nvim_win_is_valid(win) then
        local last = view.state.buf and vim.api.nvim_buf_line_count(view.state.buf) or s.line
        pcall(vim.api.nvim_win_set_cursor, win, { math.min(s.line, last), 0 })
      end
    end
  end)
end

-- One-key tagging and priorities (helpers/org/tagging.lua): the plain
-- B/F/C toggle :bug:/:feat:/:chore: and <M-a>/<M-b>/<M-c> the A/B/C
-- priority on the entry at point. Every toggle is registered as an agenda
-- action named in the specs' `action` field, and `mappings.agenda` in the
-- plugin spec binds it -- the way toggle_done above does; the plain B / F /
-- C defaults (bulk action, follow mode, clock report) are reassigned there
-- to make room. The hook runs inside `require 'org.agenda.view'`, before
-- view.open builds the agenda mappings from that table.
local function setup_one_key()
  require('org.lazy').on_load('org.agenda.view', 'one_key', function(view)
    local tagging = require 'helpers.org.tagging'
    for _, spec in ipairs(tagging.tags) do
      local tag = spec.tag
      view.actions[spec.action] = view.on_item(function(target)
        return tagging.toggle_tag(tag, target)
      end, 'lines')
    end
    for _, spec in ipairs(tagging.priorities) do
      local value = spec.value
      view.actions[spec.action] = view.on_item(function(target)
        return tagging.toggle_priority(value, target)
      end, 'lines')
    end
  end)
end

-- Entering an entry from the list (RET = switch_to, <Tab> = goto) lands in
-- the entry's file, in whatever fold state the buffer was last left in: the
-- #+STARTUP rule is applied when a buffer is loaded, not when it is shown
-- again, and a file open unfolded in another window stays unfolded here.
-- helpers/org/folding.lua show_jump_target re-applies the rule and unfolds
-- the entered tree; the wrappers below run it after the jump. The action
-- table is read when the agenda mappings are built, so both are wrapped the
-- way toggle_done is registered above.
local function setup_entry_folds()
  require('org.lazy').on_load('org.agenda.view', 'entry_folds', function(view)
    for _, name in ipairs { 'switch_to', 'goto' } do
      local action = view.actions[name]
      if action then
        view.actions[name] = function(...)
          local result = action(...)
          require('helpers.org.folding').show_jump_target()
          return result
        end
      end
    end
  end)
end

-- <CR> on an entry opens only that entry in the view's own window, so a
-- long project file's other headlines stay out of the way; the old <CR>
-- behaviour -- switch_to, the entry opened in its file -- moves to <S-CR>
-- and `o` (mappings.agenda.switch_to below, with the default `show`
-- unbound to free the key). <Space> stays the leader in the view: no key
-- binds it there. The buffer is a scratch: acwrite (so `:w` runs
-- the write hook below instead of touching a file), wiped when
-- left, `q` puts the view back (`buffer #`, the hidden agenda). It takes the
-- entry's own lines from its file -- headline through the end of its
-- subtree -- so it shows what the file holds now, unsaved edits included. It
-- is editable: `:w` splices the buffer back into its file in place of the
-- entry and writes it. The entry's start is marked with an extmark in the
-- source buffer, so a write after edits elsewhere in the file still lands on
-- the entry; the subtree range is recomputed at the mark each time. The
-- window wraps by default, its previous wrap value restored when the scratch
-- goes. Leaving the scratch never asks to save it (nothing about it looks
-- unsaved to nvim, see the guard below) and keeps the edits: the buffer is
-- written back on the way out as well as on `:w`, so `q` and every buffer
-- command answer nvim's "Save changes to ...?" with yes instead of raising
-- it. Registered as an agenda action named in the spec, the way toggle_done
-- is above.
local function setup_entry_scratch()
  require('org.lazy').on_load('org.agenda.view', 'entry_scratch', function(view)
    local ns = vim.api.nvim_create_namespace 'org_entry_scratch'
    -- `win_override` is the window the scratch goes into; the mapping leaves
    -- it out and the view's own window is taken over. The `L` preview pane
    -- (setup_entry_preview below) passes its own window instead, so the view
    -- stays on screen.
    view.actions.entry_scratch = function(win_override)
      local item = view.item_at_cursor()
      if not (item and item.headline) then
        return
      end
      local target = view.resolve_target(item)
      if not target then
        return
      end
      local src = target.bufnr
      local hl = require('org.files').get_buffer(src):headline_at(target.lnum)
      if not hl then
        return
      end
      local lines = vim.api.nvim_buf_get_lines(src, hl.line - 1, hl.end_line, false)
      local span = hl.end_line - hl.line + 1
      local mark = vim.api.nvim_buf_set_extmark(src, ns, hl.line - 1, 0, { right_gravity = false })

      local win = win_override or vim.api.nvim_get_current_win()
      local prev_wrap = vim.wo[win].wrap
      local buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].buftype = 'acwrite'
      vim.bo[buf].bufhidden = 'wipe'
      vim.bo[buf].swapfile = false
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      local base = (hl.title and hl.title ~= '' and hl.title or 'entry'):gsub('[%s/\\]', '_')
      -- A scratch of the same entry -- or of one sharing its title -- can
      -- still be alive when this one is built: the `L` pane rebuilds its
      -- scratch when the entry it holds changes under it
      -- (setup_entry_preview). nvim refuses to give two buffers one name, so
      -- take the first free one rather than leave the new scratch unnamed
      -- (its name is how the pane and `:ls` tell it apart).
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
      -- Remember where the copy came from. The buffer is a preview of one
      -- source entry, so entry commands that read the buffer under the
      -- cursor (helpers/org/ai.lua's <leader>ai) must resolve to `src` --
      -- and to the entry's first line, kept by the extmark as the file is
      -- edited -- instead of treating the scratch's `org-entry://` name as a
      -- file. Write_back reads the same pair.
      vim.b[buf].org_entry_source = src
      vim.b[buf].org_entry_mark = mark
      -- Show the buffer before it becomes an org buffer: the FileType hooks
      -- (org.nvim's buffer setup, helpers/org/mappings.lua) reach for the
      -- buffer with nvim_buf_call, and on a buffer no window shows that call
      -- opens a temporary window at the top left (aucmd_prepbuf), which a
      -- redraw in the hook then paints over the view -- a flash the preview
      -- pane, which builds one scratch per entry, would show on every move.
      vim.api.nvim_win_set_buf(win, buf)
      vim.bo[buf].filetype = 'org'
      vim.wo[win].wrap = true
      -- The preview is a scratch holding a copy of the entry; it is written
      -- back into the source file in place of the entry (the extmark keeps
      -- the position across edits elsewhere in the file).
      local dirty = false
      local function write_back()
        if not vim.api.nvim_buf_is_valid(src) or not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        local pos = vim.api.nvim_buf_get_extmark_by_id(src, ns, mark, {})
        local line = (pos[1] or (hl.line - 1)) + 1
        local cur = require('org.files').get_buffer(src):headline_at(line)
        local from = cur and cur.line or line
        local to = cur and cur.end_line or (from + span - 1)
        vim.api.nvim_buf_set_lines(src, from - 1, to, false, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        vim.api.nvim_buf_set_extmark(src, ns, from - 1, 0, { id = mark, right_gravity = false })
        if vim.api.nvim_buf_get_name(src) ~= '' then
          vim.api.nvim_buf_call(src, function()
            vim.cmd 'silent! write'
          end)
        end
        dirty = false
        vim.b[buf].org_entry_dirty = nil
      end

      -- nvim must never believe the preview holds unsaved work. With
      -- `confirm` on it checks the modified flag for every command that
      -- drops a buffer -- `:bdelete`, `:bwipeout`, `:edit`, `:enew`,
      -- `:close` -- before any buffer autocommand fires, so clearing it in
      -- QuitPre (which only covers `:q` / `:wq` / `:qa`) left the rest
      -- asking "Save changes to ...?". The flag is dropped again after
      -- every change and the buffer is tracked as `dirty` instead: the
      -- answer to that question is always yes -- `:w` and leaving the
      -- preview both write the edits back (write_back), so nothing is lost
      -- and the prompt cannot come back. `:w` still runs the write hook
      -- (BufWriteCmd fires on an unmodified acwrite buffer). `dirty` is kept
      -- on the buffer as well (`org_entry_dirty`), because the preview pane
      -- (setup_entry_preview below) replaces the buffer under its caller's
      -- feet: a buffer swapped out from inside an autocommand is wiped
      -- without its BufHidden / BufWipeout running, so the pane writes the
      -- edits back itself before the swap instead of leaving it to the
      -- handlers below.
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
          -- leaving the preview is the other "yes": an edited preview is
          -- written back rather than dropped -- but only while it still
          -- holds the entry. `:edit` on the scratch reloads the
          -- (nonexistent) file and empties it, and writing that back would
          -- wipe the entry out of its file. QuitPre is here for `:q` on the
          -- last window, where the buffer never gets hidden (nvim exits
          -- first).
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
            pcall(vim.api.nvim_buf_del_extmark, src, ns, mark)
          end
        end,
      })
    end
  end)
end

-- `L` opens a preview pane beside a view: the entry at the cursor in a
-- scratch window to the right, the same lines `<CR>` shows (headline
-- through the end of its subtree), so a long list can be read through
-- without leaving it. While the pane is open, moving the cursor onto
-- another entry reloads it, and so does an edit to the entry it already
-- holds -- a note added with `z` under the cursor, say -- which would
-- otherwise leave the pane showing the lines it was built with
-- (copy_stale below); `L` again, `q` in the pane, or leaving the view
-- closes it. The pane holds the very scratch `<CR>` opens, aimed at the
-- pane's own window instead of the view's (entry_scratch above takes a
-- target window), so it is editable and writes back the same way: an entry
-- edited in the pane is spliced into its file when the cursor moves on,
-- when the pane is closed, and on `:w`. Registered as an agenda action
-- named in the spec (`L`), the way toggle_done above is.
local function setup_entry_preview()
  local state = { win = nil, key = nil, aug = nil, placeholder = nil, pending = false }

  local function teardown()
    if state.aug then
      pcall(vim.api.nvim_del_augroup_by_id, state.aug)
    end
    state.aug, state.win, state.key, state.placeholder = nil, nil, nil, nil
  end

  --- Splice a dirty scratch back into its file. The scratch's own write-back
  --- rides on its BufHidden / BufWipeout, which do not run for a buffer
  --- swapped out from inside an autocommand -- and the pane's swap is one --
  --- so the pane writes it back itself, before the swap.
  local function flush(buf)
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == 'acwrite' and vim.b[buf].org_entry_dirty then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd 'write'
      end)
    end
  end

  local function close()
    local win = state.win
    teardown()
    if win and vim.api.nvim_win_is_valid(win) then
      flush(vim.api.nvim_win_get_buf(win))
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  --- Close from an autocommand (the view going away, a window close): the
  --- flush inside `close` is a `:write`, refused while an autocommand runs,
  --- so it waits for the main loop.
  local function close_soon()
    vim.schedule(close)
  end

  --- The entry under the cursor, as a key that changes when it does.
  local function entry_key(view)
    local item = view.item_at_cursor()
    if not (item and item.headline) then
      return nil
    end
    return (item.filename or tostring(item.bufnr)) .. ':' .. tostring(item.lnum)
  end

  --- Whether the pane's copy has fallen behind its source. The pane holds one
  --- entry's lines as they were when it was built, so a note added to that
  --- entry (`z` in the view, `<leader>n` in its file) -- or any other edit
  --- landing in it -- leaves the copy showing the older text while the entry's
  --- key (file and headline line) is unchanged, and `fill` below would keep
  --- it. Compare the copy to the entry's lines as they are now. A copy with an
  --- edit of its own is left alone: the pane writes that back on the next move
  --- (flush), so the user's text is never dropped under them.
  local function copy_stale(view)
    local buf = vim.api.nvim_win_get_buf(state.win)
    if vim.b[buf].org_entry_dirty then
      return false
    end
    local item = view.item_at_cursor()
    local target = item and item.headline and view.resolve_target(item)
    local src = target and target.bufnr
    if not src or src ~= vim.b[buf].org_entry_source then
      return false
    end
    local hl = require('org.files').get_buffer(src):headline_at(target.lnum)
    if not hl then
      return false
    end
    local now = vim.api.nvim_buf_get_lines(src, hl.line - 1, hl.end_line, false)
    return not vim.deep_equal(now, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  end

  --- Put the entry at the cursor in the pane, when it is not the one already
  --- there. The buffer is built by entry_scratch, aimed at the pane's window;
  --- the pane gets its own `q` / `L` (close it) in place of entry_scratch's
  --- `q`, which would put the view's buffer back in that window. A copy left
  --- behind by an edit to the same entry (copy_stale above) is rebuilt the
  --- same way, so a note added to the entry under the cursor shows up.
  local function fill()
    if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
      return
    end
    local view = require 'org.agenda.view'
    local key = entry_key(view)
    if key and (key ~= state.key or copy_stale(view)) then
      local before = vim.api.nvim_win_get_buf(state.win)
      flush(before)
      view.actions.entry_scratch(state.win)
      local buf = vim.api.nvim_win_get_buf(state.win)
      if buf ~= before then
        state.key = key
        local desc = 'org: close the entry preview'
        vim.keymap.set('n', 'q', close, { buffer = buf, desc = desc })
        vim.keymap.set('n', 'L', close, { buffer = buf, desc = desc })
        return
      end
    end
    -- Nothing to show: the pane keeps the entry it already holds. If it
    -- never got one -- `open` saw an entry, entry_scratch could not resolve
    -- it after all -- the empty split is dropped instead of left behind.
    if state.key == nil and vim.api.nvim_win_get_buf(state.win) == state.placeholder then
      close()
    end
  end

  --- Ask for a fill. The work runs on the main loop, not in the caller's
  --- context: the cursor moves that ask for it are autocommands, and both
  --- the flush above and entry_scratch's own write-back are `:write` calls,
  --- which nvim refuses there ("No matching autocommands for buftype=acwrite
  --- buffer", E676). Repeated asks coalesce into one fill.
  local function refresh()
    if state.pending then
      return
    end
    state.pending = true
    vim.schedule(function()
      state.pending = false
      fill()
    end)
  end

  local function open(view)
    local vwin = view.state.win
    if not (vwin and vim.api.nvim_win_is_valid(vwin)) then
      return
    end
    -- A line with no entry on it (a group header, a calendar line) has
    -- nothing to preview: leave the keys alone, the way `<CR>` does.
    if not entry_key(view) then
      return
    end
    local vbuf = vim.api.nvim_win_get_buf(vwin)
    local placeholder = vim.api.nvim_create_buf(false, true)
    vim.bo[placeholder].bufhidden = 'wipe'
    local width = math.min(math.max(40, math.floor(vim.o.columns * 0.45)), math.max(vim.o.columns - 30, 20))
    local ok, win = pcall(vim.api.nvim_open_win, placeholder, false, { split = 'right', win = vwin })
    if not (ok and win) then
      return
    end
    vim.api.nvim_win_set_width(win, width)
    vim.wo[win].winfixwidth = true
    state.win, state.placeholder = win, placeholder
    state.aug = vim.api.nvim_create_augroup('OrgEntryPreview', { clear = true })
    vim.api.nvim_create_autocmd('CursorMoved', {
      group = state.aug,
      buffer = vbuf,
      callback = refresh,
      desc = 'org: preview the entry the cursor moves to',
    })
    vim.api.nvim_create_autocmd({ 'BufHidden', 'BufWipeout' }, {
      group = state.aug,
      buffer = vbuf,
      callback = close_soon,
      desc = 'org: close the entry preview with the view',
    })
    vim.api.nvim_create_autocmd('WinClosed', {
      group = state.aug,
      pattern = tostring(win),
      callback = teardown,
      desc = 'org: forget the entry preview when its window closes',
    })
    -- Fill now, not on the next tick: `open` runs on a key, not in an
    -- autocommand, so the pane can come up with the entry already in it
    -- instead of an empty split for a frame.
    fill()
  end

  local function toggle()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      close()
      return
    end
    open(require 'org.agenda.view')
  end

  require('org.lazy').on_load('org.agenda.view', 'entry_preview', function(view)
    view.actions.entry_preview = toggle
    -- A re-render can move the entry under the cursor without a CursorMoved
    -- (a state change elsewhere, the tree watcher): follow it here too.
    view.refresh_hooks.entry_preview = function()
      if state.win then
        refresh()
      end
    end
  end)
end

-- The agenda -- and the TODO view, which renders into the same buffer -- is
-- read-only, so it must be in Normal mode: anything that lands insert or
-- terminal mode in it is left again. Two ways it lands:
--   * launching from a terminal window: the terminal's autocommands
--     (autocommands.lua: TermOpen / FocusGained / BufEnter term://*) call
--     startinsert, and it applies to the agenda buffer right after it is
--     set (logged: FileType orgagenda, then InsertEnter buftype=nofile
--     name=agenda);
--   * coming back to it: a window switch out of a capture (still in insert
--     mode, helpers/org/mappings.lua) or a tmux pane switch bringing the
--     focus back re-enters the view with the mode it had.
-- The rules are buffer-local, so they die with the view. `agenda.window =
-- 'current'` means the view takes over the window it was opened in, so the
-- current buffer right after open is the agenda one. The wrapper is
-- installed when org.agenda first loads (the agenda command requiring it),
-- which is before any of its functions run.
-- A TODO-style view lists entries (a `todo`, `tags_todo`, `search`, ... block);
-- an agenda view draws the day grid, and there the cursor belongs on today's
-- header (org.nvim's own rule). The difference is the block type.
local function is_todo_view(view)
  if not view then
    return false
  end
  for _, block in ipairs(view.blocks or { view }) do
    if block.type == 'agenda' then
      return false
    end
  end
  return true
end

-- Opening a view takes the focused window over (agenda.window = 'current'),
-- so a view already on screen stays there until something puts its buffer
-- back. Pressing the key that opened it should do that: hide it, the same
-- as `q` (view/window.lua quit -- the agenda buffer stays loaded, hidden,
-- and the buffer the view took over comes back). `§` opens the date views
-- and `°` the entry lists, and the two render into the same orgagenda
-- buffer, so the view's own blocks say which is on screen (is_todo_view
-- above): the key hides only its own kind -- from the other one it opens,
-- which reads as switching between the views.
---@param kind 'agenda'|'todo' what the key opens
---@param open fun() the view's open function
function M.toggle_view(kind, open)
  local view = require 'org.agenda.view'
  local state = view.state_of(vim.api.nvim_get_current_buf())
  if state and state.view and is_todo_view(state.view) == (kind == 'todo') then
    view.quit(false)
    return
  end
  open()
end

-- org.nvim puts the cursor on the first item of a TODO list when it opens one
-- (view/window.lua: today's header in agenda views, else the first item), but
-- that placement is a pcall'd best effort and the buffer is reused: a view
-- opened while the previous one is still on screen, or one refreshed by a
-- capture or by the AI sync (helpers/org/ai.lua), can leave the cursor off the
-- entries. Re-assert "first item" on every entry into a TODO-style view -- on
-- an agenda view it does nothing, so today's header stays.
--
-- The re-assert lands on the current window, so it only runs while that window
-- still shows the view: the deferred call below can be queued by the entry
-- into the view and run after the window has already moved on -- a capture
-- opening from the view queues it and takes over the window before the
-- callback fires (a big board defers it by seconds) -- and driving another
-- buffer's window with the view's item lines moves it: `^` from the view
-- typed the entry on the date header, one line under the `%?` the template
-- put the cursor on.
local function focus_first_item(buf)
  local view = require 'org.agenda.view'
  local state = view.state_of(buf)
  if not (state and is_todo_view(state.view)) then
    return
  end
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return
  end
  local items = state.line_items or {}
  if items[vim.api.nvim_win_get_cursor(win)[1]] then
    return
  end
  local lines = vim.tbl_keys(items)
  table.sort(lines)
  if lines[1] then
    pcall(vim.api.nvim_win_set_cursor, win, { lines[1], 0 })
  end
end

local function setup_open()
  require('org.lazy').on_load('org.agenda', 'window_setup', function(agenda)
    local agenda_open = agenda.open
    -- org.nvim reuses one agenda buffer (org://agenda, bufhidden=hide), so
    -- the rules go on once per buffer, not once per open.
    local guarded = {}
    agenda.open = function(spec, opts)
      local ok, err = pcall(agenda_open, spec, opts)
      if not ok then
        error(err)
      end
      local buf = vim.api.nvim_get_current_buf()
      focus_first_item(buf)
      local function normal_mode()
        if vim.api.nvim_get_current_buf() ~= buf then
          return
        end
        local mode = vim.api.nvim_get_mode().mode
        if mode == 't' then
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true), 'n', false)
        elseif mode:sub(1, 1) == 'i' then
          pcall(vim.cmd, 'stopinsert')
        end
      end
      normal_mode()
      if guarded[buf] then
        return
      end
      guarded[buf] = true
      vim.api.nvim_create_autocmd('InsertEnter', {
        buffer = buf,
        -- stopinsert during InsertEnter does not take; leave after
        callback = function()
          vim.defer_fn(normal_mode, 0)
        end,
        desc = 'org: leave insert mode in the agenda',
      })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
        buffer = buf,
        callback = function()
          vim.defer_fn(normal_mode, 0)
          vim.defer_fn(function()
            focus_first_item(buf)
          end, 0)
        end,
        desc = 'org: leave insert mode / first item when landing on the agenda',
      })
    end
  end)
end

-- Number keys open the custom views configured in
-- lua/terminal_plugins/org.nvim.lua (agenda.custom_commands): 1 all open
-- TODOs across every project, 2 the group view -- the whole project file,
-- split by state, not just the headline cwd's project resolved to -- 3 the
-- board (in progress, bugs, features, chores, untagged, done), 4 priorities,
-- 5 the wayfinder map of the cwd project, drawn as its charted tree (the `y`
-- command, lua/terminal_plugins/org.nvim.lua).
-- Buffer-local to orgagenda -- the TODO view renders into the same buffer,
-- so it switches from there too -- which is why the keys are the plain
-- digits and not the `<leader>o` ones: a count typed in the agenda
-- (`<C-u>` style) no longer starts with 1 or 2, and nothing else claims
-- them. `agenda.window = 'current'` makes the open take the window over, so
-- the same buffer is refilled and this reads as switching view rather than
-- stacking a second agenda.
--
-- 2's group view exists because one file can host several projects, one per
-- top-level headline (a `:PROJECT_DIRS:` headline claim each, like
-- allitude.org's "Classificazioni EVO" / "Controlla EVO" / "PMS"): cwd
-- resolves to the one headline covering it, and that is a sub-header of a
-- file holding the whole group. `2` lists the whole file -- every headline
-- of it -- by keeping the file scope (`files`, so no other project leaks
-- in) but dropping the subtree restriction, and by running the `g` command
-- (lua/terminal_plugins/org.nvim.lua): one section per open keyword
-- (NEXT/PEND/WARN/TODO), each ordered by the last-changed date the column
-- shows, under the file's own name (open_custom_view heads a file-scope
-- block with it). What the old division -- a section per project inside the
-- file -- said, the entry lines now say themselves: the category column
-- carries the sub-project's name (helpers/org/project.lua item_name). 3, 4
-- and 5 (and `°`, which opens the same `w` board through M.custom_view) are
-- scoped to the project of the working directory the way `°` was: each
-- block's `files` becomes the project's file and a headline claim adds its
-- subtree restriction. A cwd that names no project -- or one whose file
-- does not exist yet -- opens the full view, the same one the dispatcher
-- menu's `w` / `p` / `y` give. Resolution runs per key press (project.current
-- reads getcwd, or the job cwd of a terminal buffer), so a `cd` moves the
-- scope with it. 1 is global: it never scopes, so it lists the open TODOs
-- of every project.
local CUSTOM_VIEWS = {
  -- key, custom_commands key, desc, scope (see open_custom_view)
  { '1', 'o', 'all open TODOs', 'global' },
  { '2', 'g', 'the whole project file, by state', 'file' },
  { '3', 'w', 'in progress, bugs, features, chores, untagged and done', 'project' },
  { '4', 'p', 'open A/B priorities', 'project' },
  { '5', 'y', 'wayfinder: the charted map, open leaves takeable', 'project' },
}

-- The group headers the custom views draw: the global super_agenda groups
-- (lua/terminal_plugins/org.nvim.lua) with the nameless catch-all swapped
-- for a title map, so the entries are headed by the project file's title
-- (the "Nvim" of "Nvim [30/35]") instead of "Category: nvim" -- and, in the
-- agenda, no header at all (the entries follow the last named group). The
-- map depends on the scope:
--   * `'global'` (key 1) heads every file's entries with the file title;
--   * `'project'` (the board, priorities) returns '' (an empty section name
--     draws no header, and every item still lands in a section, so the
--     "Other items" heading does not appear either): the category is the
--     same under every section -- "Category: nvim" repeated -- and each
--     block header already names the project ("Nvim - Bugs, open").
-- A block that brings its own `super_groups` -- the board's Bugs / Features
-- / Chores / Untagged sections and the group view's per-state ones, which
-- both split by state -- keeps them (open_custom_view below); key 1's `o`
-- block sets none, so it takes the map above. The "In progress" block sets
-- `super_groups = false` and is not grouped at all.
-- The list is read and copied at open time, so the agenda's own groups --
-- the day view keeps the globals -- are untouched.
local function view_groups(scope)
  local project = require 'helpers.org.project'
  local out = {}
  for _, group in ipairs(require('org.extensions').opts('super_agenda').groups or {}) do
    if group.auto_map then
      local replacement = vim.deepcopy(group)
      if scope == 'project' then
        replacement.auto_map = function()
          return ''
        end
      else
        replacement.auto_map = function(item)
          return item.filename and project.file_title(item.filename) or nil
        end
      end
      out[#out + 1] = replacement
    else
      out[#out + 1] = vim.deepcopy(group)
    end
  end
  return out
end

---@param scope 'global'|'file'|'project' 'global' lists every agenda file;
---  'file' lists the cwd project's file whole (the command it opens brings
---  its own groups); 'project' narrows it to cwd's project (a headline
---  claim's subtree included)
local function open_custom_view(key, label, scope)
  local command = (require('org.config').opts.agenda.custom_commands or {})[key]
  if not command then
    require('org.utils').warn('agenda: no custom command ' .. key)
    return
  end
  local spec, opts = vim.deepcopy(command), nil
  local project = require 'helpers.org.project'
  local current = scope ~= 'global' and project.current() or nil
  local in_project = current ~= nil and vim.uv.fs_stat(current.file) ~= nil
  local groups = view_groups(scope)
  local files, title, group
  if in_project then
    files = project.files(current)
    if scope == 'project' then
      title = project.title(current)
    else
      group = project.group_title(current.file)
    end
  end
  for _, block in ipairs(spec.types or { spec }) do
    -- a block with its own groups keeps them; the board's state sections
    -- set them in the config, and its flat Done section opts out with
    -- `super_groups = false` (org-super-agenda leaves such a block ungrouped)
    if block.super_groups == nil then
      block.super_groups = groups
    end
    if files then
      -- the file scope keeps every headline of it; the project scope's
      -- block header is drawn (view.title is not), so the project name goes
      -- there: an empty view -- a project with no bug, say -- still says
      -- what it filtered on instead of looking broken
      block.files = files
      if title then
        block.header = block.header and (title .. ' - ' .. block.header) or title
      elseif group then
        -- the group view's top title: the whole file's name, its per-state
        -- sections below it (the `g` command's GROUP_SECTIONS)
        block.header = group
      end
    end
  end
  if scope == 'project' and in_project then
    local restrict = project.restrict(current)
    if restrict then
      opts = { restrict = restrict }
    end
  end
  require('org.utils').run(function()
    require('org.agenda').open(spec, opts)
  end)
end

--- Open a `custom_commands` view by its key, the same the agenda buffer's
--- number keys run (helpers.org.project.todo_view opens the `w` board this
--- way). Scoped to the cwd's project like the `3` / `4` keys; `global`
--- (`1`) skips the scope, and `file` lists the cwd
--- project's whole file (the `2` group view's command brings the per-state
--- groups itself). The `label` the keymaps pass is only their `desc`,
--- so the key stands in for it.
---@param key string a key of agenda.custom_commands
---@param scope 'global'|'file'|nil scope (see open_custom_view); nil is 'project'
function M.custom_view(key, scope)
  open_custom_view(key, key, scope or 'project')
end

local function setup_custom_views()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'orgagenda',
    callback = function(args)
      for _, view in ipairs(CUSTOM_VIEWS) do
        local key, command, label, scope = view[1], view[2], view[3], view[4] or 'project'
        vim.keymap.set('n', key, function()
          open_custom_view(command, label, scope)
        end, { buffer = args.buf, desc = 'org: Agenda view ' .. key .. ' (' .. label .. ')' })
      end
    end,
  })
end

-- Splice `text` into the builder at `pos` (1-based, before the line already
-- there) and shift the line-indexed tables the builder carries with it --
-- the highlight rows (0-based), the `items` / `line_hls` / `line_ctx` /
-- `entry_text_lines` / `day_lines` / `super_headers` maps keyed by line, and
-- `block_starts` (render.view) -- so the block that already wrote its header
-- keeps it. `group` highlights the new row; nil leaves it plain, which is
-- what a blank line gets.
local function insert_line(b, pos, text, group)
  table.insert(b.lines, pos, text)
  for _, h in ipairs(b.hls) do
    if h[1] >= pos - 1 then
      h[1] = h[1] + 1
    end
  end
  if group then
    b.hls[#b.hls + 1] = { pos - 1, 0, #text, group }
  end
  for _, key in ipairs { 'items', 'line_hls', 'line_ctx', 'entry_text_lines', 'day_lines', 'super_headers' } do
    local t = b[key]
    if t then
      local moved = {}
      for k, v in pairs(t) do
        moved[k >= pos and k + 1 or k] = v
      end
      b[key] = moved
    end
  end
  for i, s in ipairs(b.block_starts or {}) do
    if s >= pos then
      b.block_starts[i] = s + 1
    end
  end
end

-- A full-width `─` rule line, what the extension's `add_separator` draws for
-- a one-character `header_separator`. Used for the board's Done section,
-- which carries `rule_above`.
local function insert_rule(b, pos, width)
  insert_line(b, pos, string.rep('─', math.max((width or 80) - 1, 10)), 'OrgSuperAgendaSeparator')
end

-- Close the badge of every group header the grouper drew from line `first`
-- on: the header text opens with the `header_prefix` space, so one more at
-- the end balances it, and the surface0 background the theme gives
-- OrgSuperAgendaHeader (theme_catpuccin.lua) then reads as a label instead
-- of a highlight stopping at the last letter. The space goes at the end
-- column of the header's own highlight -- not the end of the line, since a
-- folded header carries the ` … (N)` suffix after the label -- so the
-- suffix stays outside the badge; the highlights that start at or run past
-- that column shift right with it. Starts at `first` because
-- `b.super_headers` accumulates over a builder's blocks: only the headers
-- this grouper call drew get their space, once.
local function close_badges(b, first)
  local col_of = {}
  for _, h in ipairs(b.hls) do
    if h[4] == 'OrgSuperAgendaHeader' and h[1] + 1 > first then
      col_of[h[1] + 1] = math.max(col_of[h[1] + 1] or 0, h[3])
    end
  end
  for lnum, col in pairs(col_of) do
    local text = b.lines[lnum]
    b.lines[lnum] = text:sub(1, col) .. ' ' .. text:sub(col + 1)
    for _, h in ipairs(b.hls) do
      if h[1] == lnum - 1 and h[3] > 0 then
        if h[2] >= col then
          h[2] = h[2] + 1
        end
        if h[3] >= col then
          h[3] = h[3] + 1
        end
      end
    end
  end
end

-- True while `render.view` is drawing a board (setup_board_view below), the
-- one thing the grouper needs to know about the view it is called from: the
-- board is where the between-block separator is off, so every section must
-- carry the blank line that tells it apart from the next (see render.grouper).
local board_render = false

-- A board state section is one block whose `super_groups` split it into the
-- per-state subsections (TODO / PEND / ...): the section reads as its header
-- underlined by a `─` rule, then its subsections told apart by blank lines.
-- The extension draws the rule with `header_separator`, before every group's
-- header, so the render runs with it set to `─` (the subsections' separator)
-- and puts the option back whatever the render did; the rules after the
-- first -- the one under the section's own header, the subsections' -- are
-- blanked afterwards (the header_separator already gave them a line). A
-- block marked `hide_empty` with nothing in it is dropped instead: the
-- header `insert_header` already wrote is taken back off the builder (with
-- its `block_starts` entry), and the grouper reports the block rendered so
-- the (empty) list is not drawn under nothing. A block marked `rule_above`
-- gets a `─` rule on the line before its header (insert_rule), which is how
-- the board sets the Done section apart from the open ones. This wraps the
-- grouper super_agenda installs through its own on_load for the same module,
-- so it must run after it: on_load runs a module's hooks sorted by key, and
-- the key here sorts after super_agenda's.
local function setup_board_sections()
  require('org.lazy').on_load('org.agenda.render', 'super_agenda_sections', function(render)
    local grouper = render.grouper
    if not grouper then
      return
    end
    -- lines insert_header writes for `block`'s header (the same split it
    -- does: `\n`, blank lines dropped; "" and nil are the no-header cases)
    local function header_lines(block)
      local h = block.header
      if type(h) == 'function' then
        h = h()
      end
      return #vim.split(tostring(h or ''), '\n', { trimempty = true })
    end
    render.grouper = function(b, rows, block, ctx, add, day)
      local hidden = block and block.hide_empty and #rows == 0
      if hidden then
        for _ = 1, header_lines(block) do
          table.remove(b.lines)
        end
        if b.block_starts and #b.block_starts > 0 then
          table.remove(b.block_starts)
        end
        return true
      end
      -- On the board the between-block separator is off (setup_board_view),
      -- so each section carries the blank line that tells it apart from the
      -- next: the grouped ones end with one (`final_group_separator`), a flat
      -- block -- the "In progress" list -- writes none, and its entries would
      -- run straight into the next header. That blank is put above this
      -- section's header instead (insert_header has just written it, at the
      -- block's start): nothing is added when the line above is blank
      -- already (a grouped section left its own) or when there is nothing
      -- above (the first section on screen).
      if board_render and block and b.block_starts and #b.block_starts > 0 and header_lines(block) > 0 then
        local pos = b.block_starts[#b.block_starts]
        if pos > 1 and b.lines[pos - 1] ~= '' then
          insert_line(b, pos, '')
        end
      end
      if block and block.rule_above and b.block_starts and #b.block_starts > 0 then
        local pos = b.block_starts[#b.block_starts]
        -- nothing above (every open section was empty): a rule would top the view
        if pos > 1 then
          insert_rule(b, pos, ctx.width)
        end
      end
      local first = #b.lines
      if not (block and block.state_sections and block.super_groups) then
        local ok, result = pcall(grouper, b, rows, block, ctx, add, day)
        if not ok then
          error(result, 0)
        end
        if result then
          close_badges(b, first)
        end
        return result
      end
      local opts = require('org.extensions').opts 'super_agenda'
      local header, final = opts.header_separator, opts.final_group_separator
      opts.header_separator = '─'
      opts.final_group_separator = '\n'
      local start = b.block_starts and b.block_starts[#b.block_starts] or 1
      local ok, result = pcall(grouper, b, rows, block, ctx, add, day)
      opts.header_separator = header
      opts.final_group_separator = final
      if not ok then
        error(result, 0)
      end
      -- keep the rule under the section's header, blank the ones the
      -- subsections got: a `─` line is empty of anything else, and only the
      -- separator writes one line above a group header (b.super_headers)
      if result then
        local kept = false
        for l = start, #b.lines do
          local text = b.lines[l]
          if text ~= '' and b.super_headers[l + 1] and text:gsub('─', '') == '' then
            if kept then
              b.lines[l] = ''
              local row = l - 1
              local hls = {}
              for _, h in ipairs(b.hls) do
                if h[1] ~= row then
                  hls[#hls + 1] = h
                end
              end
              b.hls = hls
            else
              kept = true
            end
          end
        end
        close_badges(b, first)
      end
      return result
    end
  end)
end

-- A board view is several sections, and org.nvim joins blocks with
-- org-agenda-block-separator, a rule by default (render.view). On the board
-- a rule belongs inside a section -- it splits the per-state subsections the
-- grouper draws -- so the between-block one is turned off: each section
-- leaves the blank line from the final separator above, and that is what
-- separates them. The flat sections -- "In progress", which draws no
-- separator of its own -- get theirs from the grouper (setup_board_sections),
-- which puts it above the header of the section that follows. The option is
-- the view-wide default, read when the view is rendered; a `block_separator`
-- a block sets itself is untouched (with_block_options restores it around the
-- block anyway). `board_render` tells the grouper which render it is in.
local function setup_board_view()
  require('org.lazy').on_load('org.agenda.render', 'board_block_separator', function(render)
    local view = render.view
    if not view then
      return
    end
    render.view = function(v, ctx)
      local board = false
      for _, block in ipairs(v.blocks or {}) do
        if block.state_sections then
          board = true
          break
        end
      end
      if not board then
        return view(v, ctx)
      end
      local acfg = require('org.config').opts.agenda
      local separator = acfg.block_separator
      acfg.block_separator = false
      board_render = true
      local ok, result = pcall(view, v, ctx)
      board_render = false
      acfg.block_separator = separator
      if not ok then
        error(result, 0)
      end
      return result
    end
  end)
end

-- An entry under a headline project of its file (project.M.item_name) is
-- labelled with that project's name instead of the file's own category: the
-- "Nvim" board lists "Org-Roam"'s entries under "Org-Roam:", not "nvim".
-- item_parts is the one place a line is built -- it reads item.category both
-- for the prefix (`%c`) and for the face it gives the category span -- so the
-- override is set for that build and put back afterwards, leaving the item as
-- the plugin built it (the sort and filter that read its category elsewhere
-- are untouched).
--
-- render.prefix is wrapped the same way, and for the same reason: the TODO
-- view's tree (helpers/org/tree.lua) measures the prefix off `render.prefix`
-- -- to trim it from a child line and to indent a subtree under its ancestor
-- -- so it has to read the prefix the line actually carries, the project name
-- included. Left unwrapped it reads the entry's file category instead, a
-- shorter string, and trims that much too little: the child line keeps the
-- tail of the prefix (`24  `, `om: `) and the subtree is indented by the
-- difference.
local function setup_item_category()
  require('org.lazy').on_load('org.agenda.render', 'item_category', function(render)
    local item_parts = render.item_parts
    local prefix = render.prefix
    --- Run `fn` with `item.category` the sub-project's name, then put it back,
    --- whatever `fn` returns or raises.
    local function with_project(item, fn)
      local name = require('helpers.org.project').item_name(item.headline)
      if not name or name == item.category then
        return fn()
      end
      local category = item.category
      item.category = name
      local ok, out = pcall(fn)
      item.category = category
      if not ok then
        error(out, 0)
      end
      return out
    end
    render.item_parts = function(item, ctx)
      return with_project(item, function()
        return item_parts(item, ctx)
      end)
    end
    render.prefix = function(item, kind)
      return with_project(item, function()
        return prefix(item, kind)
      end)
    end
  end)
end

-- The category column is a fixed width -- the `%-12:c` of the prefix format
-- -- so a project whose name is longer than that (the norm: "Maydaysound.com"
-- is 15) overflowed it and pushed the changed-date, the keyword and the
-- title of its own line to the right of the lines around it: one column of
-- the view, as many widths as there are category lengths. The list is aligned
-- by measuring the entries a block actually shows -- the widest category
-- among them decides the column, and every line of that block pads to it.
--
-- `render.apply_limits` is the one hook that sees a list block's entries
-- after the filters, the sort and the limits -- the list the lines are then
-- built from -- and the ctx it is handed is the one those lines carry
-- (`b.line_ctx`, the context org-agenda-change-all-lines re-formats a line
-- with), so the width is recorded there and read back per line by
-- `render.item_parts` through the format `render.prefix_format` builds -- the
-- one M.prefix compiles: the width goes into the format's category spec, the
-- rest of the format (the changed-date column, a `%(lua expression)`) is left
-- alone. The context of the line being built is kept in `active`, because
-- M.prefix -- the call inside item_parts -- is passed the kind alone; the
-- tree (helpers/org/tree.lua) passes its own context to `render.prefix`
-- explicitly, since the prefix it trims has to be the one the line carries.
--
-- An empty category draws nothing whatever the width (fmt_width skips an
-- empty field), so such a line cannot be aligned and is left as it is. The
-- configured width is a floor: a block whose widest category is shorter than
-- the format asks for keeps the format's column, so a small project's view
-- reads as it did.
local function setup_category_width()
  require('org.lazy').on_load('org.agenda.render', 'item_category_width', function(render)
    local prefix_format = render.prefix_format
    local item_parts = render.item_parts
    local prefix = render.prefix
    local apply_limits = render.apply_limits
    -- the kinds whose entries carry the category column; the day agenda's
    -- grid lines keep the format they always had
    local KINDS = { todo = true, tags = true, search = true }
    -- the category spec of a prefix format: `%c`, with its optional `?`, its
    -- width, its precision, and the separator that follows the category (`:`
    -- in `%-12:c`) -- the field's padding covers the separator too
    local SPEC = '%%(%??)([-+]?[%d]*)([%.]?[%d]*)([ .;,:!?=|/<>]?)c'
    -- the context of the line being built; M.prefix gets the kind alone
    local active

    --- The separator the format puts after the category.
    local function cat_sep(fmt)
      local _, _, _, sep = fmt:match(SPEC)
      return sep or ''
    end

    --- The width the format asks the category column to have.
    local function cat_width(fmt)
      local _, w = fmt:match(SPEC)
      return tonumber((w or ''):match '^[-+]?(%d+)' or '') or 0
    end

    --- The category the line will carry: the name of the project a headline
    --- claim names, the override item_parts applies around the build.
    local function category_of(item)
      return require('helpers.org.project').item_name(item.headline) or item.category or ''
    end

    --- Run `fn` with `ctx` the context of the line being built, so the format
    --- the prefix is compiled from carries its width.
    local function with_context(ctx, fn)
      if not ctx then
        return fn()
      end
      local prev = active
      active = ctx
      local ok, out = pcall(fn)
      active = prev
      if not ok then
        error(out, 0)
      end
      return out
    end

    render.prefix_format = function(kind)
      local fmt = prefix_format(kind)
      local width = active and active.category_width
      if not width or not KINDS[kind] then
        return fmt
      end
      return (fmt:gsub(SPEC, function(opt, _, prec, sep)
        return '%' .. opt .. '-' .. width .. prec .. sep .. 'c'
      end))
    end

    render.item_parts = function(item, ctx)
      return with_context(ctx, function()
        return item_parts(item, ctx)
      end)
    end

    render.prefix = function(item, kind, ctx)
      return with_context(ctx or active, function()
        return prefix(item, kind)
      end)
    end

    render.apply_limits = function(list, kind, ctx)
      local out = apply_limits(list, kind, ctx)
      if ctx and KINDS[kind or ''] then
        local fmt = prefix_format(kind)
        local sep, width = cat_sep(fmt), cat_width(fmt)
        for _, it in ipairs(out) do
          local w = vim.api.nvim_strwidth(category_of(it))
          if w > 0 and w + #sep > width then
            width = w + #sep
          end
        end
        ctx.category_width = width
      end
      return out
    end
  end)
end

-- <leader>ai on an entry launches an `omp` instance for that ticket in a
-- tmux pane (helpers/org/ai.lua), shadowing the global plain-omp terminal
-- key in the agenda and in the TODO view, which renders into the same
-- buffer. Buffer-local, so it lands after org.nvim's own mappings. A group
-- node -- a headline with subnodes in todo -- launches those subnodes, one
-- instance each, instead of the container itself; a Visual selection
-- launches every entry the selection covers, the same way (launch_range).
-- <leader>aj focuses the pane of that ticket's already-running instance,
-- resuming its session when none is running.
local function setup_ai()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'orgagenda',
    callback = function(args)
      vim.keymap.set('n', '<leader>ai', function()
        require('helpers.org.ai').launch()
      end, { buffer = args.buf, desc = 'org: OMP on the ticket at point' })
      vim.keymap.set('x', '<leader>ai', function()
        require('helpers.org.ai').launch_range()
      end, { buffer = args.buf, desc = 'org: OMP on the selected tickets' })
      vim.keymap.set('n', '<leader>aj', function()
        require('helpers.org.ai').jump()
      end, { buffer = args.buf, desc = 'org: jump to the running OMP for the ticket' })
    end,
  })
end

-- A capture started from the agenda or the TODO view (`^` there, the global
-- capture key, is left free by agenda.filter_top_headline = false) leaves
-- the list showing what it showed before the new entry existed: org.nvim
-- stores the entry and fires OrgCaptureAfterFinalize, but never re-renders
-- the agenda, and the view is only rebuilt on a redo (`gr`, or `r` off an
-- entry line -- on one, helpers/org/tree.lua refiles) or when it is opened
-- again. Finish the capture and put the view back on screen instead --
-- close_session restores the window the capture was started from, so the
-- current buffer here is the orgagenda one -- and re-render it. The User
-- autocmd is global but the callback leaves every other capture (a normal
-- org buffer's) alone; the view module is required only when it fires.
-- The `°` TODO view of a headline project (helpers/org/project.lua) scopes
-- the agenda to that headline's subtree with a line range, fixed when the
-- view opens. A capture started from the view files its entry at the end of
-- the subtree -- past that end -- so the re-render the capture triggers
-- would drop the entry it just wrote and leave the view looking unchanged.
-- Recompute the range from the claim headline before every render. The
-- restriction carries the headline's text, so the headline is found again
-- even after edits shift its line (the anchor the plugin's own restriction
-- lock uses, org/agenda/init.lua); a restriction without it -- the lock,
-- which tracks its subtree through a buffer extmark -- is left alone.
local function setup_restrict_refresh()
  require('org.lazy').on_load('org.agenda.view', 'restrict_refresh', function(view)
    local refresh = view.refresh
    view.refresh = function(...)
      local r = view.state and view.state.restrict
      if r and r.filename and r.range and r.raw then
        local ok, file = pcall(function()
          return require('org.files').get(r.filename)
        end)
        -- the claim headline is normally still on its line; its text is the
        -- fallback for when edits above it shifted the line (a capture that
        -- bumped the entry counts changed the text, so it is tried second)
        local hl = ok and file and (file:headline_on(r.range[1]) or file:find_headline(function(h)
          return h.raw == r.raw
        end))
        if hl then
          r.range = { hl.line, hl.end_line }
        end
      end
      return refresh(...)
    end
  end)
end

local function setup_capture_refresh()
  vim.api.nvim_create_autocmd('User', {
    pattern = 'OrgCaptureAfterFinalize',
    callback = function(args)
      if args.data and args.data.aborted then
        return
      end
      if vim.bo[vim.api.nvim_get_current_buf()].filetype ~= 'orgagenda' then
        return
      end
      require('org.agenda.view').refresh()
    end,
    desc = 'org: re-render the agenda after a capture filed from it',
  })
end

function M.setup()
  setup_toggle_done()
  setup_redo_stay()
  setup_one_key()
  setup_entry_folds()
  setup_entry_scratch()
  setup_entry_preview()
  setup_open()
  setup_custom_views()
  setup_board_sections()
  setup_board_view()
  setup_item_category()
  setup_category_width()
  setup_restrict_refresh()
  setup_capture_refresh()
  setup_ai()
end

return M
