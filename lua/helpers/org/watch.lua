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
-- callback (a reload of every changed org buffer -- in place when no window
-- shows it, helpers/org/write.lua -- plus an agenda redo) should run once per
-- quiet period. The callback is scheduled, so it never runs inside the libuv
-- callback, and it is handed the paths that changed in the burst: a subscriber
-- that reads the file rather than the buffer (helpers/org/web/init.lua) has no
-- other way to tell which of the tree's files it should send.
local M = {}

local uv = vim.uv or vim.loop

local handles = {}
local timer
local callbacks = {}
local started = false

--- The paths changed since the last dispatch, as a set.
---@type table<string, boolean>
local pending = {}

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
      local paths = vim.tbl_keys(pending)
      pending = {}
      for _, callback in ipairs(vim.deepcopy(callbacks)) do
        local ok, err = pcall(callback, paths)
        if not ok then
          vim.notify('org watch: ' .. tostring(err), vim.log.levels.WARN)
        end
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
    pending[vim.fs.normalize(dir .. '/' .. filename)] = true
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

--- Register `fn` to run (scheduled, debounced) after any org file in the
--- tree changes on disk, with the paths that changed in the burst. The tree is
--- only walked once; every subscriber shares it, so two modules can watch the
--- same vault.
---@param fn fun(paths: string[])
function M.subscribe(fn)
  for _, existing in ipairs(callbacks) do
    if existing == fn then
      return
    end
  end
  callbacks[#callbacks + 1] = fn
end

---@param fn fun(paths: string[])
function M.unsubscribe(fn)
  callbacks = vim.tbl_filter(function(cb)
    return cb ~= fn
  end, callbacks)
end

--- Watch the org tree rooted at `root` and run `fn(paths)` (scheduled,
--- debounced) after any org file in it changes on disk. Every call adds a
--- subscriber; the first one walks the tree, the rest only join.
---@param root string path, `~` and relative accepted
---@param fn fun(paths: string[])
function M.start(root, fn)
  M.subscribe(fn)
  if started then
    return
  end
  started = true
  for _, dir in ipairs(tree(vim.fs.normalize(vim.fn.expand(root)))) do
    watch(dir)
  end
end

--- Stop watching and drop every subscriber.
function M.stop()
  callbacks = {}
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
