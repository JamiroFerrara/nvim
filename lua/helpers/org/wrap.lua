-- Org wraps prose (`lua/autocommands.lua`), but a `#+begin_src` body is code:
-- wrapping it breaks the alignment the language reads by. `wrap` is
-- window-local and org has no per-region option, so the window is unwrapped
-- while the cursor is inside a src block, and its previous value restored
-- when the cursor leaves it. The block ranges are read from the buffer text
-- and cached per `changedtick`: a cursor move costs a lookup, a scan only
-- happens after an edit.
local M = {}

local group = vim.api.nvim_create_augroup('org_src_nowrap', { clear = true })
local cache = {}

local BEGIN = '^%s*#%+begin_src'
local END = '^%s*#%+end_src'

--- Whether org's `wrap` handling applies to `buf`: a real org buffer or its
--- capture/entry scratch (acwrite), not the agenda views or a nofile helper.
---@param buf integer
---@return boolean
local function org_buffer(buf)
  local buftype = vim.bo[buf].buftype
  return vim.bo[buf].filetype == 'org' and (buftype == '' or buftype == 'acwrite')
end

--- The `[first, last]` line pairs of every src block in `buf`, the `#+begin_src`
--- and `#+end_src` lines included; an unterminated block runs to the last line.
---@param buf integer
---@return table
local function src_ranges(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local hit = cache[buf]
  if hit and hit.tick == tick then
    return hit.ranges
  end
  local ranges = {}
  local start
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local lower = line:lower()
    if start then
      if lower:match(END) then
        ranges[#ranges + 1] = { start, i }
        start = nil
      end
    elseif lower:match(BEGIN) then
      start = i
    end
  end
  if start then
    ranges[#ranges + 1] = { start, #lines }
  end
  cache[buf] = { tick = tick, ranges = ranges }
  return ranges
end

--- Whether `lnum` holds a line of a src body, the fence lines excluded.
---@param buf integer
---@param lnum integer
---@return boolean
local function in_src(buf, lnum)
  for _, range in ipairs(src_ranges(buf)) do
    if lnum > range[1] and lnum < range[2] then
      return true
    end
  end
  return false
end

--- Unwrap the window while the cursor sits in a src body, restore its value
--- (whatever the user had, not a hardcoded `true`) on the way out.
local function update()
  local buf = vim.api.nvim_get_current_buf()
  if not org_buffer(buf) then
    return
  end
  local saved = vim.w.org_src_wrap
  if in_src(buf, vim.api.nvim_win_get_cursor(0)[1]) then
    if saved == nil then
      vim.w.org_src_wrap = vim.wo.wrap
      vim.wo.wrap = false
    end
  elseif saved ~= nil then
    vim.wo.wrap = saved
    vim.w.org_src_wrap = nil
  end
end

local function restore()
  if vim.w.org_src_wrap == nil then
    return
  end
  vim.wo.wrap = vim.w.org_src_wrap
  vim.w.org_src_wrap = nil
end

function M.setup()
  vim.api.nvim_create_autocmd({
    'FileType',
    'BufEnter',
    'BufWinEnter',
    'WinEnter',
    'CursorMoved',
    'CursorMovedI',
    'TextChanged',
    'TextChangedI',
  }, {
    group = group,
    callback = function(args)
      -- on the buffer/window events the FileType hooks that set `wrap` (and
      -- the startup visibility) have not necessarily run yet: defer to the
      -- end of the loop so the saved value is the buffer's own
      if args.event == 'FileType' or args.event == 'BufEnter' or args.event == 'BufWinEnter' or args.event == 'WinEnter' then
        vim.schedule(update)
      else
        update()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufLeave', 'WinLeave' }, {
    group = group,
    callback = function()
      if org_buffer(vim.api.nvim_get_current_buf()) then
        restore()
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args)
      cache[args.buf] = nil
    end,
  })
end

return M
