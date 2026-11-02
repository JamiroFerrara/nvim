-- A property drawer, collapsed to one chip on the line it belongs to (wired
-- in lua/terminal_plugins/org.nvim.lua).
--
-- A ticket carries four to six lines of `:PROPERTIES:` under its title and
-- none of it is meant to be read: `:PROPERTIES:`, `:END:` and one line per
-- key. The drawer's lines are hidden while the cursor is elsewhere and one
-- glyph takes their place at the end of the headline -- the mark of an id
-- (`md-identifier`) and the first eight characters of the `:ID:`, which is
-- enough to tell two tickets apart and to paste into a link, while the whole
-- id stays in the file.
--
-- Hidden, never removed. `conceal_lines` follows 'conceallevel' like every
-- other conceal in the buffer (nothing is hidden at 0, which is what
-- helpers/org/decorations.lua and links.lua already rely on), and the drawer
-- is drawn raw while the cursor is inside it -- a `:`, a search, a jump that
-- lands on one of its lines -- so the properties stay editable; insert mode
-- reveals it too ('concealcursor'). The chip is virtual text: the file keeps
-- exactly the lines it had.
--
-- Only the property drawer: a `:LOGBOOK:` or a drawer of the user's own is
-- left as written.
local M = {}

local NS = vim.api.nvim_create_namespace 'org_drawer'

-- md-identifier (U+F0EFE), one cell wide in the Nerd Fonts Material Design
-- range, so the chip never shifts the text it follows.
local ICON = '󰻾'

-- the chip's text color, in lua/terminal_plugins/theme_catpuccin.lua
local CHIP = 'OrgDrawerChip'

-- what the last pass drew, per buffer: the tick of the text, the drawer rows
-- and which of them were left open, so a cursor move that never crosses a
-- drawer -- and a redraw with no edit -- costs one comparison
local drawn = {}

--- The property drawer `owner` carries: its first and last row, and the row
--- its chip goes on (the headline's own line; the line above for the file's
--- drawer, which has no headline).
---@param owner table the headline, or the file for its own drawer
---@return { start: integer, stop: integer, row: integer }?
local function drawer_of(owner)
  local r = owner.properties_range
  if not r then
    return nil
  end
  return { start = r[1], stop = r[2], row = owner.line or (r[1] - 1) }
end

--- The chip of the drawer of `owner`: the icon and the head of its `:ID:`
--- when it has one, the icon alone when it does not.
---@param owner table the headline, or the file for its own drawer
---@return string
local function chip_of(owner)
  local id = (owner.properties or {}).ID
  return id and (ICON .. ' ' .. id:sub(1, 8)) or ICON
end

--- The rows of the buffer a window of `bufnr` has its cursor on.
---@param bufnr integer
---@return table<integer, boolean>
local function cursor_rows(bufnr)
  local rows = {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    rows[vim.api.nvim_win_get_cursor(win)[1]] = true
  end
  return rows
end

--- The drawers of `bufnr`, the buffer's own first.
---@param bufnr integer
---@return { start: integer, stop: integer, row: integer, chip: string }[]
local function drawers(bufnr)
  local ok, file = pcall(function()
    return require('org.files').get_buffer(bufnr)
  end)
  if not ok or not file then
    return {}
  end
  local owners = { file }
  vim.list_extend(owners, file.headlines)
  local out = {}
  for _, owner in ipairs(owners) do
    local d = drawer_of(owner)
    if d then
      d.chip = chip_of(owner)
      out[#out + 1] = d
    end
  end
  return out
end

--- The drawers the cursor is inside: those are the ones left whole.
---@param list { start: integer, stop: integer }[]
---@param cursor table<integer, boolean>
---@return table<integer, boolean>
local function open(list, cursor)
  local out = {}
  for i, d in ipairs(list) do
    for row = d.start, d.stop do
      if cursor[row] then
        out[i] = true
        break
      end
    end
  end
  return out
end

--- Whether a cursor moved since the last pass and crossed no drawer's edge:
--- the marks on the buffer are still right then, and the pass is skipped.
---@param c table
---@param now table<integer, boolean>
---@return boolean
local function untouched(c, now)
  for i, d in ipairs(c.list) do
    local inside = false
    for row = d.start, d.stop do
      if now[row] then
        inside = true
        break
      end
    end
    if inside ~= (c.open[i] == true) then
      return false
    end
  end
  return true
end

--- Whether the buffer is drawn with lines concealable: `conceal_lines` shows
--- nothing at 'conceallevel' 0 or 1 (see `:h 'conceallevel'`), and a chip over
--- a drawer still on screen would say the same thing twice.
---@param bufnr integer
---@return boolean
local function concealable(bufnr)
  local wins = vim.fn.win_findbuf(bufnr)
  return wins[1] ~= nil and vim.wo[wins[1]].conceallevel >= 2
end

--- Collapse the drawers of `bufnr` again.
---@param bufnr integer
function M.refresh(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= 'org' then
    return
  end
  if not concealable(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    drawn[bufnr] = nil
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cursor = cursor_rows(bufnr)
  local c = drawn[bufnr]
  if c and c.tick == tick and untouched(c, cursor) then
    return
  end
  local list = drawers(bufnr)
  local opened = open(list, cursor)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  local hidden = {}
  for i, d in ipairs(list) do
    if not opened[i] then
      for row = d.start, d.stop do
        local line = lines[row]
        if line then
          hidden[row] = true
          pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, row - 1, 0, {
            end_row = row - 1,
            end_col = #line,
            conceal_lines = '',
            invalidate = true,
            undo_restore = false,
          })
        end
      end
      local line = lines[d.row]
      if line and not hidden[d.row] then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, d.row - 1, #line, {
          virt_text = { { '  ' .. d.chip, CHIP } },
          virt_text_pos = 'inline',
          right_gravity = false,
        })
      end
    end
  end
  drawn[bufnr] = { tick = tick, list = list, open = opened }
end

function M.setup()
  -- any colorscheme can repaint the chip (catppuccin's custom_highlights
  -- does, in terminal_plugins/theme_catpuccin.lua); this link is the
  -- fallback
  vim.api.nvim_set_hl(0, CHIP, { link = 'Comment', default = true })
  local group = vim.api.nvim_create_augroup('org_drawer', { clear = true })
  vim.api.nvim_create_autocmd({
    'BufEnter',
    'BufWinEnter',
    'TextChanged',
    'TextChangedI',
    'CursorMoved',
    'CursorMovedI',
    'WinEnter',
    'WinLeave',
    'InsertLeave',
    'FileType',
  }, {
    group = group,
    callback = function(ev)
      M.refresh(ev.buf)
    end,
  })
  -- 'conceallevel' decides whether a line can be hidden at all, and a window
  -- may change it without any of the events above (the markdown plugin sets
  -- it when it renders an org buffer)
  vim.api.nvim_create_autocmd('OptionSet', {
    group = group,
    pattern = 'conceallevel',
    callback = function()
      M.refresh(vim.api.nvim_get_current_buf())
    end,
  })
  -- The org buffers opened before this ran have their drawer shown still.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'org' then
      vim.schedule(function()
        M.refresh(buf)
      end)
    end
  end
end

return M
