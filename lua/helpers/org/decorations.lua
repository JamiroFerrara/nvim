-- Post-processing of org.nvim's decorations (wired in
-- lua/terminal_plugins/org.nvim.lua). One wrapper, three concerns, because
-- org.ui.decorations has a single `compute` slot to replace:
--
--   * Checkbox rendering, like the markdown config: `- [ ] text` shows as
--     `- <icon> text`, the icon standing in for the box (`ui.checkboxes`
--     holds the glyphs). The stock renderer overlays the icon over `[ ]`
--     and, for icons narrower than the three columns of the box, wraps it
--     in literal brackets (`-[]`), which is what looked broken. The mark the
--     renderer computes is rewritten here into a conceal of the three box
--     columns with the icon character, so the line renders exactly as the
--     markdown plugin's.
--   * Note headers written by helpers/org/notes.lua and the omp write-back:
--     `[ts] ------` -- or `🤖 [ts] ------`, the agent's block, whose header
--     carries the icon -- gets the timestamp highlighted and the dash run
--     replaced by a rule that reaches the window edge, like the markdown
--     plugin's `---`. The agent's header is painted with the `OrgAgent*`
--     groups (icon and timestamp together, rule likewise), so a 🤖 turn reads
--     apart from the plain notes at a glance.
--   * Tables, drawn like the markdown plugin's pipe_table (style "full"):
--     the `|` separators become `│`, the `|---+---|` rule the matching
--     `├───┼───┤`, and a top/bottom border frames the first and last row.
--     The frame comes from one canonical grid for the whole table -- the
--     widest cell of each column, measured as the cells display (a cell's
--     concealed markup measures zero, see `width`), the indent of the
--     leftmost `|` -- and every row is padded to it with inline virtual
--     text. So a ragged table (org pads a table only on TAB) and a cell
--     whose markup Vim conceals both render framed and aligned: the
--     written source does not decide the alignment, the display does.
--
-- The wrapper is installed when org.ui.decorations first loads, so the
-- renderer stays out of startup.
local M = {}

-- Draw the `[timestamp] <dashes>` header of a note (helpers/org/notes.lua, and
-- the omp write-back with its 🤖 block icon in front): highlight the bracketed
-- timestamp and overlay the dash run with a rule of `─` reaching the window
-- edge. A long virtual text is clipped at the edge, so it fills any window
-- width and survives a resize without recomputing.
local RULE = string.rep('─', 400)

local function note_headers(bufnr, first, last, rows)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first, last + 1, false)
  for i, line in ipairs(lines) do
    local ts_s, ts_e = line:find '%[[^%]]+%]'
    local d_s = line:find '%-%-%-+%s*$'
    -- before the timestamp: the indent, and on an agent block the icon (🤖,
    -- written by the omp write-back) -- any non-ASCII glyph, never a word
    local head = ts_s and line:sub(1, ts_s - 1) or ''
    if ts_s and d_s and d_s > ts_e and head:match '^%s*[\128-\255]*%s*$' then
      -- the icon marks the block as the agent's: paint the icon and the
      -- timestamp (and the rule) with the OrgAgent* groups, apart from the
      -- plain notes' OrgTimestampInactive/OrgHorizontalRule
      local icon = head:find '[\128-\255]'
      local ts_group = icon and 'OrgAgentTimestamp' or 'OrgTimestampInactive'
      local rule_group = icon and 'OrgAgentRule' or 'OrgHorizontalRule'
      local row = first + i - 1
      local r = rows[row]
      if not r then
        r = {}
        rows[row] = r
      end
      r[#r + 1] = { (icon or ts_s) - 1, { end_col = ts_e, hl_group = ts_group, priority = 200 } }
      r[#r + 1] = { d_s - 1, { virt_text = { { RULE, rule_group } }, virt_text_pos = 'overlay', priority = 200 } }
    end
  end
end

-- Box-drawing glyphs of a rendered table: corners of the top, delimiter and
-- bottom rules, then the vertical and horizontal strokes (the markdown
-- config's pipe_table borders).
local TABLE = {
  top = { '┌', '┬', '┐' },
  mid = { '├', '┼', '┤' },
  bot = { '└', '┴', '┘' },
  v = '│',
  h = '─',
}

--- Byte columns (0-based) of the `|` separators of a table row. A `\|` is
--- cell content, not a separator.
---@param line string
---@return integer[]
local function separators(line)
  local out, i = {}, 0
  while true do
    local s = line:find('|', i + 1, true)
    if not s then
      return out
    end
    if s == 1 or line:sub(s - 1, s - 1) ~= '\\' then
      out[#out + 1] = s - 1
    end
    i = s
  end
end

--- Display width of the bytes [start, stop) of buffer line `lnum` (1-based)
--- as the buffer shows them: the width of the characters, minus the columns
--- syntax conceal hides in place -- the `=x=` and `*x*` markup of a cell
--- (the conceal flag of a character is what `synconcealed` reports for it,
--- and it is off while 'conceallevel' is 0, when nothing is hidden).
---@param lnum integer
---@param line string
---@param start integer 0-based byte column of the first byte
---@param stop integer 0-based byte column past the last byte
---@return integer
local function width(lnum, line, start, stop)
  local w, i = 0, start
  while i < stop do
    local len = math.min(vim.str_utf_end(line, i + 1) + 1, stop - i)
    if vim.fn.synconcealed(lnum, i + 1)[1] == 0 then
      w = w + vim.fn.strdisplaywidth(line:sub(i + 1, i + len))
    end
    i = i + len
  end
  return w
end

--- A frame row of a table: the corner at the first separator, a horizontal
--- run per cell, then the corner/tee at each following separator, from the
--- canonical separator columns of the table (`tables`), top, delimiter and
--- bottom alike.
---@param seps integer[] separator columns, display columns
---@param left string corner
---@param tee string inner junction
---@param right string corner
---@return string
local function border(seps, left, tee, right)
  local out = { string.rep(' ', seps[1]), left }
  for i = 1, #seps - 1 do
    out[#out + 1] = string.rep(TABLE.h, seps[i + 1] - seps[i] - 1)
    out[#out + 1] = i == #seps - 1 and right or tee
  end
  return table.concat(out)
end

--- Rows a table is read past the viewport before the look is capped (a
--- table taller than this keeps its frame only for the rows read).
local SPAN = 500

--- The row (0-based) of `bufnr` whose concealed text the current window's
--- cursor line shows raw: the modes 'concealcursor' leaves out (insert,
--- replace and visual at the config's "nc"), the same of org.nvim's
--- table shrink. A table row there cannot be padded -- the inline virtual
--- text is drawn next to the revealed markup -- and its separators cannot be
--- concealed, which is what nvim's 'concealcursor' asks for. nil when no row
--- of this buffer is revealed.
---@param bufnr integer
---@return integer?
local function revealed_row(bufnr)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= bufnr then
    return nil
  end
  local m = vim.api.nvim_get_mode().mode:sub(1, 1)
  local key = 'n'
  if m == 'v' or m == 'V' or m == '\22' or m == 's' or m == 'S' or m == '\19' then
    key = 'v'
  elseif m == 'i' or m == 'R' then
    key = 'i'
  elseif m == 'c' then
    key = 'c'
  end
  if vim.wo[win].concealcursor:find(key, 1, true) then
    return nil
  end
  return vim.api.nvim_win_get_cursor(win)[1] - 1
end

--- Render the tables of rows [first, last]. A table is the run of rows
--- starting with `|` that carries the row; one row beyond the range is read
--- on each side so a table cut by the viewport is not framed as if it
--- started there, and the rows past that when the table runs on, so the
--- grid is the whole table's: a row of the table on the edge of the range
--- is extended over, and the frame does not change shape with the part of
--- the table a window happens to draw (the decoration of a window is
--- computed in pieces, and the inline padding of the pieces has to agree).
local function tables(bufnr, first, last, rows)
  local n = vim.api.nvim_buf_line_count(bufnr)
  local lo = math.max(0, first - 1)
  local hi = math.min(n - 1, last + 1)
  if lo > hi then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, lo, hi + 1, false)
  if lines[1]:match '^%s*|' and lo > 0 then
    local above = vim.api.nvim_buf_get_lines(bufnr, math.max(0, lo - SPAN), lo, false)
    for k = #above, 1, -1 do
      if not above[k]:match '^%s*|' then
        break
      end
      lo = lo - 1
    end
    lines = vim.api.nvim_buf_get_lines(bufnr, lo, hi + 1, false)
  end
  if lines[#lines]:match '^%s*|' and hi < n - 1 then
    local below = vim.api.nvim_buf_get_lines(bufnr, hi + 1, math.min(n, hi + 1 + SPAN), false)
    for k = 1, #below do
      if not below[k]:match '^%s*|' then
        break
      end
      hi = hi + 1
    end
    lines = vim.api.nvim_buf_get_lines(bufnr, lo, hi + 1, false)
  end
  ---@param row integer
  ---@param col integer
  ---@param opts table
  ---@param persist? boolean
  local function mark(row, col, opts, persist)
    local r = rows[row]
    if not r then
      r = {}
      rows[row] = r
    end
    r[#r + 1] = { col, opts, persist }
  end
  local hl = 'OrgTableSeparator'
  local i = 1
  while i <= #lines do
    if not lines[i]:match '^%s*|' then
      i = i + 1
    else
      local s = i
      while i <= #lines and lines[i]:match '^%s*|' do
        i = i + 1
      end
      -- The rows of the run, the `|---+---|` ones flagged: the dashes of a
      -- rule count nothing in the grid (org writes them at the length of
      -- the unpadded cells, which would widen the frame on their own).
      local parsed, drawn = {}, 0
      for k = s, i - 1 do
        local line = lines[k]
        local seps = separators(line)
        -- a row may leave the closing `|` out: its last cell runs to the
        -- end of the line then
        local tail = line:find('%S', seps[#seps] + 2) ~= nil
        local rule = line:match '^%s*|[-+|%s]*$' ~= nil and line:find('-', 1, true) ~= nil
        parsed[k] = { line = line, seps = seps, rule = rule, tail = tail, n = #seps - 1 + (tail and 1 or 0) }
        if not rule then
          drawn = drawn + 1
        end
      end
      -- The canonical grid: the display column of the leftmost `|`, and one
      -- width per column, the widest of its cells as displayed. A table of
      -- rules alone (no row to measure) is measured by its rules.
      local indent, widths, ncols = nil, {}, 0
      for k = s, i - 1 do
        local r = parsed[k]
        if not r.rule or drawn == 0 then
          local left = width(lo + k, r.line, 0, r.seps[1])
          indent = not indent and left or math.min(indent, left)
          for c = 1, r.n do
            local w = width(lo + k, r.line, r.seps[c] + 1, r.seps[c + 1] or #r.line)
            if not widths[c] or w > widths[c] then
              widths[c] = w
            end
          end
          ncols = math.max(ncols, r.n)
        end
      end
      if indent then
        local seps = { indent }
        local raw = revealed_row(bufnr)
        for c = 1, ncols do
          seps[c + 1] = seps[c] + widths[c] + 1
        end
        for k = s, i - 1 do
          local row, r = lo + k - 1, parsed[k]
          if row >= first and row <= last then
            if r.rule then
              -- the overlay hides the written row; pad it out so a longer
              -- rule (dashes run past the cells above) cannot show beside it
              local text = border(seps, TABLE.mid[1], TABLE.mid[2], TABLE.mid[3])
              local pad = vim.fn.strdisplaywidth(r.line) - vim.fn.strdisplaywidth(text)
              mark(row, 0, {
                virt_text = { { text .. string.rep(' ', math.max(pad, 0)), hl } },
                virt_text_pos = 'overlay',
                end_col = #r.line,
              })
            elseif row ~= raw then
              -- (a revealed cursor line -- see `revealed_row` -- is left
              -- raw: nvim shows its concealed markup there, and a padding
              -- would land beside it)
              -- The separator of a row is concealed in place and drawn back
              -- from the grid: `pad` spaces (the columns the cell here is
              -- narrower than its column) and the glyph, so every `|` of
              -- the table lands on the same screen column -- how wide the
              -- row was written no longer matters.
              local shift = 0
              for c = 1, #r.seps do
                local pad = seps[c] - shift - width(lo + k, r.line, 0, r.seps[c])
                if pad < 0 then
                  -- a row indented past the table's leftmost `|` -- only its
                  -- first separator can sit left of the grid -- hides the
                  -- extra indent instead: nothing draws it back to the left,
                  -- and the conceal shifts the rest of the row with it
                  mark(row, 0, { end_col = math.min(-pad, r.seps[c]), conceal = '' })
                end
                mark(row, r.seps[c], {
                  end_col = r.seps[c] + 1,
                  conceal = '',
                  virt_text = { { string.rep(' ', math.max(pad, 0)) .. TABLE.v, hl } },
                  virt_text_pos = 'inline',
                })
                shift = shift + pad
              end
              -- the separators the row does not write: the `│` of a column
              -- it stops short of, and the closing `│` of a row written
              -- without a trailing `|`
              local k0 = #r.seps
              local tail = r.tail and width(lo + k, r.line, r.seps[k0] + 1, #r.line) or 0
              if not r.tail and #r.line > r.seps[k0] + 1 then
                -- blanks past the closing `|`: nothing draws them, and they
                -- would push a short row's synthesized `│` out of line
                mark(row, r.seps[k0] + 1, { end_col = #r.line, conceal = '' })
              end
              local out = {}
              for c = k0 + 1, ncols + 1 do
                local gap = c == k0 + 1 and seps[c] - seps[c - 1] - 1 - tail or widths[c - 1]
                out[#out + 1] = string.rep(' ', math.max(gap, 0)) .. TABLE.v
              end
              if #out > 0 then
                mark(row, #r.line, { virt_text = { { table.concat(out), hl } }, virt_text_pos = 'inline' })
              end
            end
            if k == s then
              local text = border(seps, TABLE.top[1], TABLE.top[2], TABLE.top[3])
              mark(row, 0, { virt_lines = { { { text, hl } } }, virt_lines_above = true }, true)
            end
            if k == i - 1 then
              local text = border(seps, TABLE.bot[1], TABLE.bot[2], TABLE.bot[3])
              mark(row, 0, { virt_lines = { { { text, hl } } } }, true)
            end
          end
        end
      end
    end
  end
end

function M.setup()
  -- Agent note blocks: any colorscheme can repaint them (catppuccin's
  -- custom_highlights does, in terminal_plugins/theme_catpuccin.lua); these
  -- links are the fallback.
  vim.api.nvim_set_hl(0, 'OrgAgentTimestamp', { link = 'Special', default = true })
  vim.api.nvim_set_hl(0, 'OrgAgentRule', { link = 'Special', default = true })
  require('org.lazy').on_load('org.ui.decorations', 'checkbox_conceal', function(decorations)
    local compute = decorations.compute
    decorations.compute = function(bufnr, first, last, ui)
      local rows = compute(bufnr, first, last, ui)
      if ui and type(ui.checkboxes) == 'table' then
        for _, marks in pairs(rows) do
          for _, m in ipairs(marks) do
            local virt_text = m[2].virt_text
            local group = virt_text and virt_text[1] and virt_text[1][2]
            local i = group == 'OrgCheckbox' and 1 or group == 'OrgCheckboxPartial' and 2 or group == 'OrgCheckboxChecked' and 3
            if i then
              -- the box `[ ]` is three bytes; conceal replaces all three with
              -- the icon (a single character)
              m[2] = {
                end_col = m[1] + 3,
                conceal = vim.fn.strcharpart(ui.checkboxes[i], 0, 1),
                hl_group = group,
              }
            end
          end
        end
      end
      local n = vim.api.nvim_buf_line_count(bufnr)
      local lo = math.max(0, first or 0)
      local hi = math.min(n - 1, last or n - 1)
      note_headers(bufnr, lo, hi, rows)
      tables(bufnr, lo, hi, rows)
      return rows
    end
    -- A table row's marks depend on the revealed row (see `revealed_row`),
    -- which a mode or a move changes without an edit: org.nvim's decorations
    -- are computed once per changedtick, so a change of that row has to drop
    -- them -- the row that was padded has to lose it, the one that became
    -- the cursor line has to be left raw.
    local revealed = {}
    vim.api.nvim_create_autocmd({ 'ModeChanged', 'CursorMoved', 'CursorMovedI', 'WinEnter', 'BufEnter' }, {
      callback = function(args)
        if vim.bo[args.buf].filetype ~= 'org' then
          return
        end
        local row = revealed_row(args.buf)
        if revealed[args.buf] ~= row then
          revealed[args.buf] = row
          decorations.render(args.buf)
        end
      end,
    })
  end)
end

return M
