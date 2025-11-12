-- Orgmode folding helpers
local M = {}

-- Fold expression for Orgmode headings
function _G.org_foldexpr()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum)
  local heading = line:match("^(%*+)%s")
  if heading then
    local level = #heading
    return ">" .. level
  end
  return "="
end

M.set_org_folding = function()
  vim.opt.foldtext = "" -- keep syntax highlighting
  vim.opt_local.foldmethod = "expr"
  vim.opt_local.foldexpr = "v:lua.org_foldexpr()"
  vim.opt_local.foldlevel = 99
end

-- This toggles folds for all headings of a given level (like your Markdown version)
M.fold_headings_of_level = function(level)
  vim.cmd("keepjumps normal! gg")
  local total_lines = vim.fn.line("$")
  for line = 1, total_lines do
    local line_content = vim.fn.getline(line)
    if line_content:match("^" .. string.rep("%*", level) .. "%s") then
      vim.cmd(string.format("keepjumps call cursor(%d, 1)", line))
      local current_foldlevel = vim.fn.foldlevel(line)
      if current_foldlevel > 0 then
        if vim.fn.foldclosed(line) == -1 then
          vim.cmd("normal! za")
        end
      end
    end
  end
end

M.fold_org_headings = function(levels)
  local saved_view = vim.fn.winsaveview()
  for _, level in ipairs(levels) do
    M.fold_headings_of_level(level)
  end
  vim.cmd("nohlsearch")
  vim.fn.winrestview(saved_view)
end

return M
