-- C# Tree-sitter folding helpers (Focused on Methods)
local M = {}

local b_folds = {}

local function update_folds(bufnr)
  local parser = require('nvim-treesitter.parsers').get_parser(bufnr)
  if not parser then return end
  local tree = parser:parse()[1]
  local root = tree:root()

  -- Specifically target code blocks we want to collapse
  local query = vim.treesitter.query.parse("c_sharp", [[
    (method_declaration) @fold
    (constructor_declaration) @fold
    (property_declaration) @fold
    (using_directive) @fold
  ]])

  local new_folds = {}
  for _, node, _ in query:iter_captures(root, bufnr) do
    local start_row, _, end_row, _ = node:range()
    
    -- If it has attributes, find the first line of the actual declaration
    -- so the [Attribute] stays visible above the fold.
    for child in node:iter_children() do
      if child:type() ~= "attribute_list" then
        start_row, _, _, _ = child:range()
        break
      end
    end

    new_folds[start_row + 1] = { type = "start", end_line = end_row + 1 }
  end
  b_folds[bufnr] = new_folds
end

function _G.cs_ts_foldexpr()
  local lnum = vim.v.lnum
  local bufnr = vim.api.nvim_get_current_buf()

  if not b_folds[bufnr] then update_folds(bufnr) end

  local line_data = b_folds[bufnr][lnum]
  
  -- 1. Start a fold at the method/property (after attributes)
  if line_data and line_data.type == "start" then
    return ">1"
  end

  -- 2. Handle whitespace (inherit fold level)
  local line = vim.fn.getline(lnum)
  if line:match('^%s*$') then
    return "=" 
  end

  -- 3. Explicitly stop folding at the end of a block or top-level keywords
  -- This prevents the "swallowing" of the whole file.
  if line:match('^namespace%s') or line:match('^public%s+partial%s+class') then
    return "0"
  end

  -- 4. Default to staying inside the fold
  return "1"
end

M.fold_csharp_methods = function()
  update_folds(0)
  local view = vim.fn.winsaveview()
  vim.cmd [[normal! zR]] -- Open all first
  
  local bufnr = vim.api.nvim_get_current_buf()
  local folds = b_folds[bufnr] or {}

  -- Close every fold we identified (Methods, Props, Usings)
  for lnum, _ in pairs(folds) do
    vim.api.nvim_win_set_cursor(0, { lnum, 0 })
    pcall(vim.cmd, 'normal! zc')
  end

  vim.fn.winrestview(view)
end

M.set_csharp_folding = function()
  _G.cs_ts_foldexpr = _G.cs_ts_foldexpr

  -- Refresh when file changes
  -- vim.api.nvim_create_autocmd({"BufWritePost", "TextChanged", "InsertLeave"}, {
  --   buffer = 0,
  --   callback = function() update_folds(0) end,
  -- })

  vim.keymap.set('n', '<leader>or', function() M.fold_csharp_methods() end, { buffer = true, desc = "Fold C# Methods" })

  vim.opt_local.foldmethod = 'expr'
  vim.opt_local.foldexpr = 'v:lua.cs_ts_foldexpr()'
  vim.opt_local.foldlevel = 99 -- Start with everything open
end

return M
