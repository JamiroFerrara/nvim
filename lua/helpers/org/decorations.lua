-- Post-processing of org.nvim's decorations (wired in
-- lua/terminal_plugins/org.nvim.lua). One wrapper, two concerns, because
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
      note_headers(bufnr, math.max(0, first or 0), math.min(n - 1, last or n - 1), rows)
      return rows
    end
  end)
end

return M
