-- Write side of the browser views (helpers/org/web/init.lua): the dashboard
-- changes an entry's TODO keyword and opens its file, and both go through
-- org.nvim's own commands, so the CLOSED stamp, the logging drawer, the
-- parent statistics and the state-change hooks behave as they do in the
-- editor.
--
-- A request names the entry by file and line, the line it was rendered at.
-- Between the render and the click the file may have moved under the entry
-- (`D` in the TUI, an agent's write-back), so the `:ID:` wins when the entry
-- has one, and the line is only a fallback for the entries that carry none.
local M = {}

--- Restrict a request path to the files the agenda reads.
---@param path string
---@return string|nil
local function agenda_path(path)
  if type(path) ~= 'string' or path == '' then
    return nil
  end
  local abs = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
  for _, known in ipairs(require('org.files').agenda_file_paths()) do
    if known == abs then
      return abs
    end
  end
  return nil
end

M.agenda_path = agenda_path

--- The buffer of `path`, loaded, and its text brought up to date with the
--- file when the buffer holds no edits of its own (an agent's write-back,
--- another editor). helpers/org/write.lua's refresh swaps the lines in
--- place and records the read, so the save after an edit can be forced
--- instead of asking a question nobody on this side of the request can
--- answer.
---@param path string
---@return integer
local function buffer_for(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(path)
  end
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end
  pcall(function()
    require('helpers.org.write').refresh(bufnr)
  end)
  return bufnr
end

--- The headline a request means: by `:ID:` when it has one, else the
--- headline owning `line`.
---@param bufnr integer
---@param line integer|nil
---@param id string|nil
---@return org.Headline|nil
local function headline_at(bufnr, line, id)
  local file = require('org.files').get_buffer(bufnr)
  if not file then
    return nil
  end
  if id and id ~= '' then
    local found = file:find_by_id(id)
    if found then
      return found
    end
  end
  if not line then
    return nil
  end
  return file:headline_at(line)
end

--- Set the TODO keyword of one entry. Returns the state it now reads, the
--- reason when nothing changed, and a warning when the change landed in the
--- buffer but could not be written (the editor's own conflict to resolve).
---@param spec { file: string, line?: integer, id?: string }
---@param state string
---@return string|nil state, string|nil error, string|nil warning
function M.set_state(spec, state)
  local path = agenda_path(spec and spec.file)
  if not path then
    return nil, 'unknown file'
  end
  local bufnr = buffer_for(path)
  local hl = headline_at(bufnr, tonumber(spec.line), spec.id)
  if not hl then
    return nil, 'entry not found'
  end
  local ok, result = pcall(require('org.todo').change_state, { bufnr = bufnr, lnum = hl.line }, state or '')
  if not ok then
    return nil, tostring(result)
  end
  if not result then
    return nil, 'state change blocked'
  end
  -- no_prompt: a request cannot answer the W12 question, so a write the
  -- module cannot prove safe is refused and reported instead of hanging
  local saved, save_err = require('helpers.org.write').save(bufnr, { no_prompt = true })
  require('helpers.org.web.data').invalidate()
  return result.new or '', nil, (not saved) and save_err or nil
end

--- Show one entry in a window of this nvim.
---@param spec { file: string, line?: integer, id?: string }
---@return boolean
function M.open(spec)
  local path = agenda_path(spec and spec.file)
  if not path then
    return false
  end
  local bufnr = buffer_for(path)
  local hl = headline_at(bufnr, tonumber(spec.line), spec.id)
  vim.api.nvim_set_current_buf(bufnr)
  if hl then
    pcall(vim.api.nvim_win_set_cursor, 0, { hl.line, 0 })
    vim.cmd 'normal! zv'
  end
  return true
end

--- The entry's subtree as exported HTML, for the dashboard's detail pane.
---@param spec { file: string, line?: integer, id?: string }
---@return string|nil html, string|nil error
function M.entry_html(spec)
  local path = agenda_path(spec and spec.file)
  if not path then
    return nil, 'unknown file'
  end
  local bufnr = buffer_for(path)
  local wanted = tonumber(spec.line) or spec.id
  local hl = wanted and headline_at(bufnr, tonumber(spec.line), spec.id) or nil
  if wanted and not hl then
    return nil, 'entry not found'
  end
  -- no headline asked for (the cursor above the first one): the whole file
  local ok, html = pcall(function()
    return require('org.export').to_string('html', {
      bufnr = bufnr,
      subtree_line = hl and hl.line or nil,
      body_only = true,
    })
  end)
  if not ok then
    return nil, tostring(html)
  end
  -- the exporter colours source blocks with Emacs' htmlize; the browser
  -- shows them the way the buffer does instead (helpers/org/web/highlight)
  return require('helpers.org.web.highlight').html(html), nil
end

return M
