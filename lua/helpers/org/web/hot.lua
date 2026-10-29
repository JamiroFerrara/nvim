-- Live reload of the website's own files.
--
-- The vault watcher (helpers/org/watch.lua) follows the org files; this one
-- follows the code that draws them: the assets a page loads and the modules
-- the server renders with. An asset is read from disk on every request
-- (helpers/org/web/page.lua), so a page that loads itself again already gets
-- the new file -- the browser only has to be told that the file changed.
--
-- libuv's fs_event is per directory, so every directory watched gets its own
-- handle; the events are filtered to the extensions the site is made of, and
-- a burst of them (an editor's temp write and the rename onto the real path)
-- is one callback, scheduled so it never runs inside the libuv callback.
local M = {}

local uv = vim.uv or vim.loop

local QUIET = 150 -- ms of quiet before a burst counts as one change

local EXTENSIONS = { lua = true, js = true, css = true, html = true }

--- Watch `dirs` for changes to the files the site is made of, and run
--- `fn(paths)` (scheduled, debounced) after each burst, with the paths that
--- changed in it.
---@param dirs string[]
---@param fn fun(paths: string[])
---@return fun()|nil stop
function M.start(dirs, fn)
  local handles = {}
  local pending = {}
  local timer

  local function flush()
    timer:stop()
    timer:close()
    timer = nil
    local paths = vim.tbl_keys(pending)
    pending = {}
    vim.schedule(function()
      fn(paths)
    end)
  end

  for _, dir in ipairs(dirs) do
    local handle = uv.new_fs_event()
    local ok = handle
      and handle:start(dir, {}, function(err, name)
        if err or not name then
          return
        end
        local ext = name:match '%.([%w]+)$'
        if not ext or not EXTENSIONS[ext:lower()] then
          return
        end
        pending[dir .. '/' .. name] = true
        if timer then
          return
        end
        timer = uv.new_timer()
        timer:start(QUIET, 0, flush)
      end)
    if ok then
      handles[#handles + 1] = handle
    elseif handle then
      handle:close()
    end
  end

  if #handles == 0 then
    return nil
  end

  return function()
    for _, handle in ipairs(handles) do
      pcall(function()
        handle:stop()
        handle:close()
      end)
    end
    handles = {}
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
  end
end

return M
