-- nvim-cmp source for `:b`/`:buffer`-style completion that previews each
-- candidate by switching the originating window to that buffer as you browse,
-- instead of showing a floating documentation popup.

local cmp = require 'cmp'

-- Canonical names returned by `nvim_parse_cmd` for the -complete=buffer commands.
local BUFFER_CMDS = {
  buffer = true,
  sbuffer = true,
  bdelete = true,
  bwipeout = true,
  bunload = true,
}

-- Live preview state: the buffer to restore when the cmdline closes.
local state = { original_buf = nil }
local preview_timer = nil

local M = {}

-- Source -------------------------------------------------------------

M.new = function()
  return setmetatable({}, { __index = M })
end

M.get_debug_name = function()
  return 'buffer_preview'
end

M.get_keyword_pattern = function()
  return [=[[^[:blank:]]*]=]
end

M.get_trigger_characters = function()
  return { ' ', '#', '-' }
end

local function resolve_bufnr(name)
  local escaped = '^' .. vim.fn.escape(name, [[~\.^$*[]]) .. '$'
  local bufnr = vim.fn.bufnr(escaped)
  return bufnr > 0 and bufnr or nil
end

M.complete = function(_, params, callback)
  local line = params.context.cursor_before_line

  local ok, parsed = pcall(vim.api.nvim_parse_cmd, line, {})
  if not ok or not parsed or not BUFFER_CMDS[parsed.cmd] then
    return callback { isIncomplete = false, items = {} }
  end

  -- The text being completed is the trailing run of non-blank chars (same as
  -- cmp-cmdline). Only produce items when it is preceded by whitespace, i.e.
  -- we are completing a buffer *argument* and not the command name itself
  -- (`:bu|` must keep showing command completions).
  local s = vim.regex '[^[:blank:]]*$':match_str(line)
  s = s or 0
  if s == 0 or not line:sub(s, s):match '%s' then
    return callback { isIncomplete = false, items = {} }
  end
  local arglead = line:sub(s + 1)

  local items = {}
  for _, name in ipairs(vim.fn.getcompletion(arglead, 'buffer')) do
    local bufnr = resolve_bufnr(name)
    items[#items + 1] = {
      label = name,
      kind = cmp.lsp.CompletionItemKind.Variable,
      data = bufnr and { bufnr = bufnr } or nil,
    }
  end

  callback { isIncomplete = false, items = items }
end

-- Live preview -------------------------------------------------------

local function restore()
  if state.original_buf and vim.api.nvim_buf_is_valid(state.original_buf) then
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_buf(win, state.original_buf)
    end
  end
  state.original_buf = nil
end

local function preview(bufnr)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) == bufnr then
    return
  end
  if state.original_buf == nil then
    state.original_buf = vim.api.nvim_win_get_buf(win)
  end
  vim.api.nvim_win_set_buf(win, bufnr)
end

local function active_bufnr()
  if not cmp.visible() then
    return nil
  end
  local entry = cmp.get_selected_entry()
  if not entry or entry.source.name ~= 'buffer_preview' then
    return nil
  end
  local data = entry:get_completion_item().data
  return data and data.bufnr or nil
end

local function do_preview_active()
  if vim.fn.getcmdtype() ~= ':' then
    return
  end
  local ok, parsed = pcall(vim.api.nvim_parse_cmd, vim.fn.getcmdline(), {})
  if not ok or not parsed or not BUFFER_CMDS[parsed.cmd] then
    restore()
    return
  end
  local bufnr = active_bufnr()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    preview(bufnr)
  end
end

local function schedule_preview()
  if preview_timer then
    preview_timer:stop()
    preview_timer:close()
    preview_timer = nil
  end
  preview_timer = vim.defer_fn(function()
    preview_timer = nil
    do_preview_active()
  end, 50)
end

---Preview the currently highlighted buffer. Call from cmdline mappings after
---moving the selection.
function M.preview_active()
  do_preview_active()
end

---Preview after a completion was triggered (menu is built asynchronously).
function M.schedule_preview()
  schedule_preview()
end

---Register the cmdline autocmds. Call once.
function M.setup()
  vim.api.nvim_create_autocmd('CmdlineLeave', {
    callback = function()
      restore()
    end,
  })
  vim.api.nvim_create_autocmd('CmdlineChanged', {
    callback = schedule_preview,
  })
end

return M
