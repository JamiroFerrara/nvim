-- Checkbox rendering for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua), like the markdown config: `- [ ] text`
-- shows as `- <icon> text`, the icon standing in for the box
-- (`ui.checkboxes` holds the glyphs). The stock renderer overlays the icon
-- over `[ ]` and, for icons narrower than the three columns of the box, wraps
-- it in literal brackets (`-[]`), which is what looked broken. The mark the
-- renderer computes is rewritten here into a conceal of the three box columns
-- with the icon character, so the line renders exactly as the markdown
-- plugin's. The wrapper is installed when org.ui.decorations first loads, so
-- the renderer stays out of startup.
local M = {}

function M.setup()
  require('org.lazy').on_load('org.ui.decorations', 'checkbox_conceal', function(decorations)
    local compute = decorations.compute
    decorations.compute = function(bufnr, first, last, ui)
      local rows = compute(bufnr, first, last, ui)
      if not ui or type(ui.checkboxes) ~= 'table' then
        return rows
      end
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
      return rows
    end
  end)
end

return M
