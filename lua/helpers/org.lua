-- Orgmode folding helpers
local M = {}

function M.smart_action()
  local line = vim.api.nvim_get_current_line()

  -- Fold if the line contains at least one '#'
  if line:find("^*") then
    vim.cmd("normal! za")
  end

  local link = require('orgmode.org.links.hyperlink').at_cursor()
  if link then
    return require('orgmode').action('org_mappings.open_at_point');
  end

  -- Default to toggling checkboxes
  return require('orgmode').action('org_mappings.toggle_checkbox');
end

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
  vim.api.nvim_set_keymap('n', '<cr>', "<cmd>lua require('helpers.org').smart_action()<cr>",
    { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<leader>or', "zR<cmd>lua require('helpers.org').fold_headings_of_level(2)<cr>",
    { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<leader>oe', "zR<cmd>lua require('helpers.org').fold_headings_of_level(3)<cr>",
    { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<leader>ow', "zR<cmd>lua require('helpers.org').fold_headings_of_level(4)<cr>",
    { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<leader>oa', "zR", { noremap = true, silent = true })
  vim.api.nvim_set_keymap('n', '<leader>oo', "zR", { noremap = true, silent = true })

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
