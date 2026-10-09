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
--   * Note headers written by helpers/org/notes.lua: `[ts] ------` gets the
--     timestamp highlighted and the dash run replaced by a rule that reaches
--     the window edge, like the markdown plugin's `---`.
--   * Tables, drawn like the markdown plugin's pipe_table (style "full"):
--     the `|` separators become `│`, the `|---+---|` rule the matching
--     `├───┼───┤`, and a top/bottom border frames the first and last row.
--     The source decides the alignment (org realigns a table on TAB), so the
--     borders line up with the separators as written.
--
-- The wrapper is installed when org.ui.decorations first loads, so the
-- renderer stays out of startup.
local M = {}

-- Draw the `[timestamp] <dashes>` header of a note (helpers/org/notes.lua):
-- highlight the bracketed timestamp and overlay the dash run with a rule of
-- `─` reaching the window edge. A long virtual text is clipped at the edge,
-- so it fills any window width and survives a resize without recomputing.
local RULE = string.rep('─', 400)

local function note_headers(bufnr, first, last, rows)
  local lines = vim.api.nvim_buf_get_lines(bufnr, first, last + 1, false)
  for i, line in ipairs(lines) do
    local ts_s, ts_e = line:find '%[[^%]]+%]'
    local d_s = line:find '%-%-%-+%s*$'
    if ts_s and d_s and d_s > ts_e and line:sub(1, ts_s - 1):match '^%s*$' then
      local row = first + i - 1
      local r = rows[row]
      if not r then
        r = {}
        rows[row] = r
      end
      r[#r + 1] = { ts_s - 1, { end_col = ts_e, hl_group = 'OrgTimestampInactive', priority = 200 } }
      r[#r + 1] = { d_s - 1, { virt_text = { { RULE, 'OrgHorizontalRule' } }, virt_text_pos = 'overlay', priority = 200 } }
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

--- A `|---+---|` rule as box drawing, one byte in one glyph: `├` and `┤` at
--- the ends, `┼` at the junctions, `─` in between.
---@param line string
---@return string
local function rule(line)
  local first, last
  for i = 1, #line do
    if line:sub(i, i) == '|' then
      first = first or i
      last = i
    end
  end
  local out = {}
  for i = 1, #line do
    local c = line:sub(i, i)
    if c == '-' then
      out[#out + 1] = TABLE.h
    elseif c == '+' or c == '|' then
      out[#out + 1] = (i == first and TABLE.mid[1]) or (i == last and TABLE.mid[3]) or TABLE.mid[2]
    else
      out[#out + 1] = c
    end
  end
  return table.concat(out)
end

--- The top or bottom border of a table row: the left corner at the first
--- separator, a horizontal run for each cell, then the corner/tee at each
--- following separator.
---@param seps integer[] separator columns of the row
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

--- Render the tables of rows [first, last]. A table is the run of rows
--- starting with `|` that carries the row; one row beyond the range is read
--- on each side so a table cut by the viewport is not framed as if it
--- started there.
local function tables(bufnr, first, last, rows)
  local lo = math.max(0, first - 1)
  local hi = math.min(vim.api.nvim_buf_line_count(bufnr) - 1, last + 1)
  if lo > hi then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, lo, hi + 1, false)
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
      for k = s, i - 1 do
        local row = lo + k - 1
        if row >= first and row <= last then
          local line = lines[k]
          if line:match '^%s*|[-+|%s]*$' and line:find('-', 1, true) then
            mark(row, 0, { virt_text = { { rule(line), hl } }, virt_text_pos = 'overlay', end_col = #line })
          else
            local seps = separators(line)
            for _, col in ipairs(seps) do
              mark(row, col, { end_col = col + 1, conceal = TABLE.v, hl_group = hl })
            end
            if #seps > 1 and k == s then
              local text = border(seps, TABLE.top[1], TABLE.top[2], TABLE.top[3])
              mark(row, 0, { virt_lines = { { { text, hl } } }, virt_lines_above = true }, true)
            end
            if #seps > 1 and k == i - 1 then
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
  end)
end

return M
