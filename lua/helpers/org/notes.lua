-- Custom note handling for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua). Replaces org.todo.add_note so a note
-- lands directly in the entry body -- newest first, above the older notes
-- and above the initial capture -- instead of being wrapped in a LOGBOOK
-- drawer, which is what `#+STARTUP: ... logdrawer` makes the stock insertion
-- do. An entry then reads as a sequence of plain blocks headed by an
-- inactive timestamp and a dash rule:
--
--   [2026-10-08 Thu 15:53] ------------------------------------------------
--   text of the note
--   [2026-10-08 Thu] ------------------------------------------------------
--   content captured when the entry was created
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

--- Insert `lines` at the top of `hl`'s body -- after the planning line and
--- property drawer, past any blank line -- so a new note reads before the
--- older ones. Indented like the entry's existing body when it has one
--- (captures and Emacs wrote theirs indented; org.nvim would otherwise drop
--- the note to column 0), else by `org.edit.body_indent`. Returns the line
--- number the first inserted line landed on.
---@param bufnr integer
---@param hl org.Headline
---@param lines string[]
---@return integer
local function insert_top(bufnr, hl, lines)
  local edit = require 'org.edit'
  local file = require('org.files').get_buffer(bufnr)
  local at = edit.meta_end(hl) + 1
  local body = file.lines
  while at <= hl.body_end and body[at] and body[at]:match '^%s*$' do
    at = at + 1
  end
  local indent = edit.body_indent(hl.level)
  if at <= hl.body_end and body[at] then
    local existing = body[at]:match '^(%s*)'
    if #existing > #indent then
      indent = existing
    end
  end
  local out = {}
  for _, l in ipairs(lines) do
    out[#out + 1] = indent .. l
  end
  vim.api.nvim_buf_set_lines(bufnr, at - 1, at - 1, false, out)
  return at
end

--- org-add-note: prompt for the note, then store it at the top of the
--- entry body (newest first). Registered as `org.todo.add_note`, so both the
--- org buffer `<leader>n` and the agenda/todo view `z` use it.
---@param target? table
---@return boolean|nil
function M.add(target)
  local edit = require 'org.edit'
  local bufnr, _, hl = edit.resolve_headline(target)
  if not bufnr then
    return nil
  end
  local utils = require 'org.utils'
  local note = utils.input_note { prompt = 'Note: ', purpose = edit.note_purpose 'note' }
  if not note or vim.trim(note) == '' then
    return nil
  end
  local date = require 'org.date'
  local ts = date.effective_now(hl):clone({ active = false }):to_string()
  local first = insert_top(bufnr, hl, entry_lines(ts, note))
  edit.note_stored(bufnr, first, hl.line)
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
