-- Live reload for the org tree: watch ~/org and call back when any .org
-- file in it changes on disk.
--
-- FocusGained (helpers/org/ai.lua) only covers an agent write-back that
-- happens while nvim is unfocused. A detached `omp` pane writes the ticket
-- file without ever taking the focus off nvim -- the tmux split / window is
-- created detached, so the pane switch the FocusGained path relies on never
-- happens -- and the TODO view would show the old state until the next
-- focus change. This watcher is what makes the view follow the file.
--
-- libuv's fs_event is per directory (inotify under the hood), never
-- recursive, so every directory of the tree gets its own handle, created
-- once at startup. Events are filtered to the org files themselves: editor
-- swap / lock / backup files (".foo.org", "foo.org~", "4913") would only
-- ring the callback. Saves are usually a rename onto the real path after a
-- temp write, which fs_event reports for the directory -- watching the
-- file itself would miss the rename, the directory does not.
--
-- Events are debounced: a single save can raise several, and the reload
-- callback (a checktime of every org buffer plus an agenda redo) should run
-- once per quiet period. The callback is scheduled, so it never runs inside
-- the libuv callback.
local M = {}

local uv = vim.uv or vim.loop

local handles = {}
local timer
local callback
local started = false

--- Coalesce a burst of events into one scheduled callback.
local function changed()
  if timer then
    return
  end
  timer = uv.new_timer()
  timer:start(120, 0, function()
    timer:stop()
    timer:close()
    timer = nil
    vim.schedule(function()
      if callback then
        callback()
      end
    end)
  end)
end

--- Watch `dir` for changes to the org files directly inside it.
---@param dir string
local function watch(dir)
  local handle = uv.new_fs_event()
  if not handle then
    return
  end
  local ok = handle:start(dir, {}, function(err, filename)
    if err or not filename then
      return
    end
    -- hidden editor by-products (emacs locks, swap files) and anything that
    -- is not an org file are noise
    if filename:sub(1, 1) == '.' or not filename:match '%.org$' then
      return
    end
    changed()
  end)
  if ok then
    handles[#handles + 1] = handle
  else
    handle:close()
  end
end

--- Every directory of the tree rooted at `root`, root included, hidden
--- directories skipped.
---@param root string
---@return string[]
local function tree(root)
  local out = {}
  local function walk(dir)
    out[#out + 1] = dir
    local ok, it = pcall(vim.fs.dir, dir)
    if not ok then
      return
    end
    for name, kind in it do
      if kind == 'directory' and name:sub(1, 1) ~= '.' then
        walk(dir .. '/' .. name)
      end
    end
  end
  walk(root)
  return out
end

--- Watch the org tree rooted at `root` and run `fn` (scheduled, debounced)
--- after any org file in it changes on disk. The first call wins; later
--- calls only update the callback.
---@param root string path, `~` and relative accepted
---@param fn fun()
function M.start(root, fn)
  callback = fn
  if started then
    return
  end
  started = true
  for _, dir in ipairs(tree(vim.fs.normalize(vim.fn.expand(root)))) do
    watch(dir)
  end
end

--- Stop watching and drop the callback.
function M.stop()
  callback = nil
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  for _, handle in ipairs(handles) do
    handle:stop()
    handle:close()
  end
  handles = {}
  started = false
end

return M
