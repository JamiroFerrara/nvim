--- Extract file paths with optional line numbers from terminal output lines.
--- Supports stack traces, grep/compiler errors, and plain paths.

local M = {}

-- Path to Brave browser executable (WSL: Windows Brave via /mnt/c).
local BRAVE = '/mnt/c/Users/JFerrara/AppData/Local/BraveSoftware/Brave-Browser/Application/brave.exe'

--- Reconstruct the full logical line from a wrapped terminal line.
--- Terminal output wraps at word boundaries; `getline('.')` only sees one
--- physical line. This walks backwards joining lines where the previous
--- line ends mid-word (no trailing whitespace) and the current line
--- starts mid-word (no leading whitespace), which is the wrapping pattern.
---@param linenr number Physical line number
---@return string
function M.collect_line(linenr)
  local lines = { vim.fn.getline(linenr) }
  local i = linenr
  while i > 1 do
    local prev = vim.fn.getline(i - 1)
    local cur  = vim.fn.getline(i)
    -- Only join wrapped lines: prev line ends mid-word (no trailing space)
    -- AND current line starts mid-word (no leading space).  This prevents
    -- concatenating independent stack-trace entries into one blob.
    if prev:gsub('%s+$', ''):match('%S$') and cur:match('^%S') then
      table.insert(lines, 1, prev)
      i = i - 1
    else
      break
    end
  end
  return table.concat(lines)
end
--- Try to extract a URL, file path, or path+line from a line of text.
--- Returns (path, type_or_line) where type_or_line is:
---   - 'url' for https?:// URLs
---   - a number (line number) for file paths with line info
---   - nil for plain file paths without line info
--- Returns (nil, nil) if nothing found.
---@param line string
---@return string|nil, (number|string|nil)
function M.parse_line(line)
  if not line or line == '' then return nil, nil end

  -- URL patterns first (checked before file paths so they take priority).
  local url = line:match('https?://[^%s<>\'"]+')
  if url then
    -- Strip trailing punctuation from the URL
    url = url:gsub('[,;)\\]}>]+$', '')
    return url, 'url'
  end

  local patterns = {
    { 'in%s+([^%s:]+%.%w+):line%s+(%d+)', true },
    { '([^%s:]+%.%w+)%((%d+)%)', true },
    { '([^%s:]+%.%w+):(%d+):', true },
    { '([^%s:]+%.%w+):(%d+)$', true },
    { '([^%s:]+%.%w+):(%d+)%s', true },
    { '([^%s:]+%.%w+),%s*line%s+(%d+)', true },
    { '([^%s:]+%.%w+)', false },
  }
  for _, p in ipairs(patterns) do
    local path, lineno = line:match(p[1])
    if path then
      if (path:match('/') or path:match('^~')) and not path:match('://') then
        if p[2] then
          return path, tonumber(lineno)
        else
          return path, nil
        end
      end
    end
  end
  return nil, nil
end

-- Base Vim regex patterns for highlighting.
-- File paths: /path/file.ext optionally followed by :N, :line N, or (N).
local BASE_PATH = [[\v(\s|^)\zs(\/|\~)\S+\.\w+(:\d+|\:line\s+\d+|\(\d+\))?\ze(\s|$|\)|\]|,|;)]]
-- URLs: https?://... until whitespace or common delimiters.
local BASE_URL  = [=[\v(\s|^)\zshttps?://[^[:space:])\]]+\ze(\s|$|\)|\]|,|;)]=]

--- Build a line-restricted pattern from a base pattern.
---@param linenr number
---@param base string
---@return string
local function line_pat(linenr, base)
  return string.format([[\v%%%dl]] .. base:sub(3), linenr)
end

-- Highlight groups -----------------------------------------------------------
-- TermPathCursor: red (theme DiagnosticError) + underline on the cursor line.
vim.api.nvim_set_hl(0, 'TermPathCursor', { link = 'DiagnosticError', underline = true, default = true })
vim.api.nvim_set_hl(0, 'TermPathUnderline', { underline = true, default = true })

-- Augroup shared across terminal buffers (clear=false so per-buffer listeners
-- accumulate without removing each other; buffer-local autocmds are cleaned up
-- when the buffer closes).
local augroup = vim.api.nvim_create_augroup('TermPathHighlight', { clear = false })

--- Apply path/URL highlights to a terminal buffer.
--- Call once from TermOpen.
function M.apply_highlights()
  -- 1. Permanent underline on all clickable content (priority 5).
  pcall(vim.fn.matchdelete, vim.b.term_path_underline_id)
  pcall(vim.fn.matchdelete, vim.b.term_path_underline_url_id)
  local ok, id = pcall(vim.fn.matchadd, 'TermPathUnderline', BASE_PATH, 5)
  if ok then vim.b.term_path_underline_id = id end
  local ok2, id2 = pcall(vim.fn.matchadd, 'TermPathUnderline', BASE_URL, 5)
  if ok2 then vim.b.term_path_underline_url_id = id2 end

  -- 2. Cursor-line red highlight (priority 10, overrides underline on that line).
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    buffer = 0,
    group = augroup,
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].buftype ~= 'terminal' then return end

      -- Clear previous cursor-line matches
      local prev = vim.b[buf].term_path_cursor_id
      if prev then
        pcall(vim.fn.matchdelete, prev)
        vim.b[buf].term_path_cursor_id = nil
      end
      local prev_url = vim.b[buf].term_path_cursor_url_id
      if prev_url then
        pcall(vim.fn.matchdelete, prev_url)
        vim.b[buf].term_path_cursor_url_id = nil
      end

      local linenr = vim.fn.line('.')
      -- Apply both path and URL patterns (matchadd only highlights when matched)
      local okp, idp = pcall(vim.fn.matchadd, 'TermPathCursor', line_pat(linenr, BASE_PATH), 10)
      if okp then vim.b[buf].term_path_cursor_id = idp end
      local oku, idu = pcall(vim.fn.matchadd, 'TermPathCursor', line_pat(linenr, BASE_URL), 10)
      if oku then vim.b[buf].term_path_cursor_url_id = idu end
    end,
  })
end


--- Handle Enter key in terminal normal mode.
--- 1. URL → open in Brave browser.
--- 2. Path (file or directory) → open in nvim buffer (oil/netrw for dirs).
--- 3. Last-token fallback → try fs_stat; if nothing found, cd in terminal.
function M.handle_enter()
  local raw_line = M.collect_line(vim.fn.line('.'))
  local trimmed = raw_line:match('^%s*(.-)%s*$')
  if not trimmed or trimmed == '' then return end

  -- 1. Try to find a path anywhere in the line (stack traces, grep, URLs)
  local t_path, t_lineno = M.parse_line(trimmed)
  if t_path then
    if t_lineno == 'url' then
      vim.fn.jobstart({ BRAVE, t_path }, { detach = true })
      return
    end
    local expanded = vim.fn.expand(t_path)
    if expanded == '' then expanded = t_path end
    if t_lineno then
      vim.cmd('edit +' .. t_lineno .. ' ' .. vim.fn.fnameescape(expanded))
    else
      vim.cmd.edit(expanded)
    end
    return
  end

  -- 2. Last-token fallback: try as a path, open in nvim if it exists
  local raw = trimmed:match('(%S+)$')
  if not raw then return end
  local path = raw:gsub('[,;)\\]}>]$', '')
  local expanded = vim.fn.expand(path)
  if expanded == '' then expanded = path end

  if vim.uv.fs_stat(expanded) then
    -- File or directory → open in nvim (dir goes through oil/netrw)
    vim.cmd.edit(expanded)
  else
    -- Not a valid path → cd in the terminal
    vim.fn.chansend(vim.b.terminal_job_id, 'cd ' .. expanded .. '\n')
    vim.cmd.startinsert()
  end
end
return M
