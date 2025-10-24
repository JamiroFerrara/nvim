local M = {}

-- TODO: Implement conditonal code folding
function M.smart_action()
  local util = require("obsidian").util
  local line = vim.api.nvim_get_current_line()

  -- Fold if the line contains at least one '#'
  if line:find("#") then
    return "za"
  end

  -- Follow link if possible
  if util.cursor_on_markdown_link(nil, nil, true) then
    return "<cmd>ObsidianFollowLink<CR>"
  end

  -- Default to toggling checkboxes
  return "<cmd>ObsidianToggleCheckbox<CR>"
end

function M.yank_code_block()
  local cursor = vim.api.nvim_win_get_cursor(0) -- {row, col}
  local row = cursor[1]
  local buf = 0
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local start_line, end_line = nil, nil

  -- First, look upward for a closing fence ```
  for i = row, 1, -1 do
    if lines[i] and lines[i]:match("^```") then
      end_line = i - 1
      -- look further up for opening fence ```
      for j = i - 1, 1, -1 do
        if lines[j] and lines[j]:match("^```") then
          start_line = j + 1
          break
        end
      end
      break
    end
  end

  -- If not found, maybe we're inside a block → find opening first
  if not start_line then
    for i = row, 1, -1 do
      if lines[i] and lines[i]:match("^```") then
        start_line = i + 1
        -- now search forward for closing ```
        for j = i + 1, #lines do
          if lines[j] and lines[j]:match("^```") then
            end_line = j - 1
            break
          end
        end
        break
      end
    end
  end

  if start_line and end_line and start_line <= end_line then
    local block = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
    vim.fn.setreg("+", table.concat(block, "\n"))
    vim.notify("Yanked code block to clipboard")
  else
    vim.notify("No code block found")
  end
end

-- Checks each line to see if it matches a markdown heading (#, ##, etc.):
-- It’s called implicitly by Neovim’s folding engine by vim.opt_local.foldexpr
function _G.markdown_foldexpr()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum)
  local heading = line:match("^(#+)%s")
  if heading then
    local level = #heading
    if level == 1 then
      -- Special handling for H1
      if lnum == 1 then
        return ">1"
      else
        local frontmatter_end = vim.b.frontmatter_end
        if frontmatter_end and (lnum == frontmatter_end + 1) then
          return ">1"
        end
      end
    elseif level >= 2 and level <= 6 then
      -- Regular handling for H2-H6
      return ">" .. level
    end
  end
  return "="
end

M.set_markdown_folding = function()
  vim.opt_local.foldmethod = "expr"
  vim.opt_local.foldexpr = "v:lua.markdown_foldexpr()"
  vim.opt_local.foldlevel = 99

  -- Detect frontmatter closing line
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local found_first = false
  local frontmatter_end = nil
  for i, line in ipairs(lines) do
    if line == "---" then
      if not found_first then
        found_first = true
      else
        frontmatter_end = i
        break
      end
    end
  end
  vim.b.frontmatter_end = frontmatter_end
end

-- FIX: This does not toggle, only close
M.fold_headings_of_level = function(level)
  -- Move to the top of the file without adding to jumplist
  vim.cmd("keepjumps normal! gg")
  -- Get the total number of lines
  local total_lines = vim.fn.line("$")
  for line = 1, total_lines do
    -- Get the content of the current line
    local line_content = vim.fn.getline(line)
    -- "^" -> Ensures the match is at the start of the line
    -- string.rep("#", level) -> Creates a string with 'level' number of "#" characters
    -- "%s" -> Matches any whitespace character after the "#" characters
    -- So this will match `## `, `### `, `#### ` for example, which are markdown headings
    if line_content:match("^" .. string.rep("#", level) .. "%s") then
      -- Move the cursor to the current line without adding to jumplist
      vim.cmd(string.format("keepjumps call cursor(%d, 1)", line))
      -- Check if the current line has a fold level > 0
      local current_foldlevel = vim.fn.foldlevel(line)
      if current_foldlevel > 0 then
        -- Fold the heading if it matches the level
        if vim.fn.foldclosed(line) == -1 then
          vim.cmd("normal! za")
        end
        -- else
        --   vim.notify("No fold at line " .. line, vim.log.levels.WARN)
      end
    end
  end
end

M.fold_markdown_headings = function(levels)
  -- I save the view to know where to jump back after folding
  local saved_view = vim.fn.winsaveview()
  for _, level in ipairs(levels) do
    M.fold_headings_of_level(level)
  end
  vim.cmd("nohlsearch")
  -- Restore the view to jump to where I was
  vim.fn.winrestview(saved_view)
end

return M
