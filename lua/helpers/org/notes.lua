-- Custom note handling for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua). Replaces org.todo.add_note so a note
-- lands directly in the entry body -- appended at the end, below the older
-- notes and below the initial capture -- instead of being wrapped in a
-- LOGBOOK drawer, which is what `#+STARTUP: ... logdrawer` makes the stock
-- insertion do. An entry then reads as a chronological log: the capture that
-- created it first, then the notes in the order they were taken, each a
-- plain block headed by an inactive timestamp and a dash rule:
--
--   [2026-10-08 Thu] ------------------------------------------------------
--   content captured when the entry was created
--
--   [2026-10-08 Thu 15:53] ------------------------------------------------
--   text of the note
--
-- Blocks are separated by a blank line, so each reads as its own turn in the
-- conversation; lines within one block stay consecutive.
--
-- A note on an entry in TEST does not stop at the note: TEST means the work
-- was handed back for validation, so a note there is the user's answer to it,
-- and storing it also launches the ticket -- helpers/org/ai.lua's launch, run
-- on the entry the note landed on (never fanned out to its children: the note
-- is on that headline). The agent then starts on the entry with the note in
-- its body, and the launcher re-stamps `NEXT`: the state it found was
-- answered by that very note, so the claim is not limited to an untouched
-- `TODO` (helpers/org/ai.lua's `claim`). Every other state stores the note
-- and nothing else.
--
-- The omp write-back (skill omp-org-ticket) writes the same block; its header
-- carries the 🤖 icon in front of the timestamp, which is what marks the
-- block as the agent's -- decorations.lua draws that header like these. Its
-- text is written in Markdown, wrapped in an org `markdown` source block.
--
-- The rule is a fixed run of dashes in the source (tools that do not render
-- still read it as a separator); helpers/org/decorations.lua overflows it to
-- the end of the window, like the markdown plugin's `---`.
--
-- The stock note buffer (`*Org Note*`) is kept, but saving it (`:w`, <C-s>)
-- finishes the note like <C-c><C-c>: the buffer is a scratch one, so a real
-- write would fail; it is made 'acwrite' and BufWriteCmd replays the store
-- mapping.
local M = {}

-- Fixed dash run in the source: the renderer overflows the rule to the
-- window edge, so the raw length only has to read as a separator.
M.DASHES = 60

--- Note text headed by `[timestamp] <rule>`, split into lines. `ts` is the
--- timestamp string already bracketed (org.date to_string).
---@param ts string
---@param note string
---@return string[]
local function entry_lines(ts, note)
  local lines = { ts .. ' ' .. string.rep('-', M.DASHES) }
  for _, l in ipairs(vim.split(note, '\n', { plain = true })) do
    lines[#lines + 1] = l
  end
  return lines
end

--- The block a turn is written as: `[<timestamp>] <rule>` over the text, one
--- line per line of it. `hl` is the entry the block lands under (its own place
--- decides "now", like every note does). The capture that creates an entry and
--- the note that answers one share this shape, so a caller writing a whole
--- entry -- the voice card's ticket, helpers/org/ai.lua -- writes the same
--- header a capture does.
---@param hl org.Headline|nil the entry the block lands under; nil for "now",
--- with no entry's own scheduling in play
---@param text string
---@return string[]
function M.block(hl, text)
  local date = require 'org.date'
  local ts = date.effective_now(hl):clone({ active = false }):to_string()
  return entry_lines(ts, text)
end

--- Append `lines` at the end of `hl`'s body -- after the last non-blank body
--- line, so a new note reads after the older ones and the subtree stays a
--- chronological log (the capture that created the entry first, then the
--- notes in the order they were taken). A blank separator is put before the
--- new block, so consecutive blocks read as separate conversations; a blank
--- separator before the next headline is left where it is. Indented like the
--- entry's existing body when it has one (captures and Emacs wrote theirs
--- indented; org.nvim would otherwise drop the note to column 0), else by
--- `org.edit.body_indent`. Returns the line number the block's header landed
--- on (past the blank separator).
---@param bufnr integer
---@param hl org.Headline
---@param lines string[]
---@return integer
local function append_block(bufnr, hl, lines)
  local edit = require 'org.edit'
  local file = require('org.files').get_buffer(bufnr)
  local body = file.lines
  local floor = edit.meta_end(hl)
  local at = hl.body_end or floor
  while at > floor and body[at] and body[at]:match '^%s*$' do
    at = at - 1
  end
  local indent = edit.body_indent(hl.level)
  local out = {}
  local first = at + 1
  if at > floor then
    local existing = body[at]:match '^(%s*)'
    if #existing > #indent then
      indent = existing
    end
    -- blank line between the previous block and this one
    out[#out + 1] = ''
    first = first + 1
  end
  for _, l in ipairs(lines) do
    out[#out + 1] = indent .. l
  end
  vim.api.nvim_buf_set_lines(bufnr, at, at, false, out)
  return first
end

--- Store `note` at the end of `hl`'s body, under the timestamp of the moment
--- it was taken (see `append_block` for the shape and the order). This is the
--- write itself, without the prompt, so a caller that already has the text --
--- the browser dashboard's note box (helpers/org/web/actions.lua) -- writes
--- the same block the editor's `<leader>n` does. Returns the line the
--- block's header landed on, or nil when the note is blank.
---@param bufnr integer
---@param hl org.Headline
---@param note string|nil
---@return integer|nil
function M.store(bufnr, hl, note)
  if not (note and vim.trim(note) ~= '') then
    return nil
  end
  local first = append_block(bufnr, hl, M.block(hl, note))
  require('org.edit').note_stored(bufnr, first, hl.line)
  return first
end

--- org-add-note: prompt for the note, then store it at the end of the entry
--- body (chronological order). Registered as `org.todo.add_note`, so both the
--- org buffer `<leader>n` and the agenda/todo view `z` use it.
---
--- A ticket whose run is still going gets the note itself: the text is typed
--- into that instance's prompt (helpers/org/ai.lua's `M.deliver_note`), so the
--- work in flight reads it as the next thing the user said instead of a second
--- instance starting beside it on the same headline. Nothing is claimed there
--- -- the run keeps the ticket.
---
--- A note on an entry nothing is running and that stands in TEST reads the
--- note back to a fresh run: the entry has been handed back for validation, so
--- the note is the user's answer to it, and storing it also launches the
--- ticket (helpers/org/ai.lua's launch, `M.launch_at`) -- the launcher claims
--- the entry back to NEXT (the note is the answer the hand-back was waiting
--- for) and omp starts with the note itself in its message -- the launcher
--- reads the newest turn off the body, so the run opens knowing what it was
--- started for instead of guessing which block of a growing body is the new
--- one. Any other state stores the note and stops there. TEST is read off the
--- headline as it was found, before the note lands below it.
---@param target? table
---@return boolean|nil
function M.add(target)
  local edit = require 'org.edit'
  local bufnr, _, hl = edit.resolve_headline(target)
  if not bufnr then
    return nil
  end
  local retest = hl.todo == 'TEST'
  local utils = require 'org.utils'
  local note = utils.input_note { prompt = 'Note: ', purpose = edit.note_purpose 'note' }
  if not M.store(bufnr, hl, note) then
    return nil
  end
  local ai = require 'helpers.org.ai'
  -- A run still on the ticket takes the note as its next message; one that
  -- handed the entry back (TEST) is started on it when nothing is running.
  if ai.deliver_note(bufnr, hl.line, note) then
    return true
  end
  if retest then
    ai.launch_at(bufnr, hl.line)
  end
  return true
end

--- Make `:w` / <C-s> in the `*Org Note*` buffer finish the note like
--- <C-c><C-c>. org.nvim fires OrgLogBufferSetup with the buffer number once
--- the note buffer exists, so this does not depend on its layout.
local function setup_save_finishes()
  vim.api.nvim_create_autocmd('User', {
    pattern = 'OrgLogBufferSetup',
    callback = function(args)
      local buf = args.data and args.data.bufnr
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      -- scratch buffer: a real write is impossible, so `:w` means "store"
      vim.bo[buf].buftype = 'acwrite'
      vim.api.nvim_create_autocmd('BufWriteCmd', {
        buffer = buf,
        once = true,
        callback = function()
          vim.api.nvim_buf_call(buf, function()
            for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
              if m.callback and m.lhs:lower() == '<c-c><c-c>' then
                m.callback()
                return
              end
            end
            -- no store mapping found: cancel rather than leave the note open
            vim.cmd 'stopinsert'
          end)
        end,
      })
    end,
  })
end

function M.setup()
  require('org.lazy').on_load('org.todo', 'helper_note', function(todo)
    todo.add_note = M.add
  end)
  setup_save_finishes()
end

return M
