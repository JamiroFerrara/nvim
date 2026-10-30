-- A commit hash in an entry is a way to its commit: put the cursor on it and
-- press <CR> (or `gx`), or click it, and the change the commit made opens as
-- a diff.
--
-- org.nvim follows a link by its syntax, and a bare hash is no link at all --
-- it is either prose or a `code` span in the markdown block a hand-back is
-- written in. So the hash is read here and given as a link: `link_at_cursor`
-- answers `git:<hash>` when the cursor sits on a hex word, and the `git:` type
-- registered in the plugin's `links.types` opens the commit. Every door that
-- follows a link -- <CR>, `gx`, a mouse click, the context menu -- then opens
-- the diff without knowing a hash from a link, and a written-out
-- `[[git:<hash>][<hash>]]` works the same.
--
-- The repository is not assumed to be the cwd: a ticket's board claims the
-- repos of its project (helpers/org/project.lua), and a hash is looked up
-- there first, then in the cwd's and the buffer's repo. A hash none of them
-- knows says so instead of opening an empty diff -- which is what a UUID's
-- first eight characters would otherwise do.
local M = {}

--- Shortest and longest hash read as one: git's own floor is 4, but a shorter
--- run is far more often a number than a commit.
local MIN, MAX = 7, 40

--- The commit hash at byte `col` (1-based) of `line`, or nil, `first` and
--- `last` its byte range. A hash is lowercase hex, holds a letter (a run of
--- digits is a year, a ticket number, not a commit) and touches no other word
--- character, so the first eight of a UUID or the tail of `0x1a2b3c4d` is no
--- hash.
---@param line string
---@param col integer
---@return string|nil word, integer|nil first, integer|nil last
local function hash_at(line, col)
  local first, last = col, col
  while first > 1 and line:sub(first - 1, first - 1):match '^%x$' do
    first = first - 1
  end
  while last < #line and line:sub(last + 1, last + 1):match '^%x$' do
    last = last + 1
  end
  local word = line:sub(first, last)
  if #word < MIN or #word > MAX or not word:match '^[0-9a-f]+$' or not word:match '[a-f]' then
    return nil
  end
  local before = first > 1 and line:sub(first - 1, first - 1) or ''
  local after = line:sub(last + 1, last + 1)
  if before:match '[%w_]' or after:match '[%w_]' then
    return nil
  end
  -- hex groups joined by `-` are a UUID or a dashed id: its first eight
  -- characters are the most common false hash on these boards, and every
  -- ticket carries one in its property drawer
  if (before == '-' and line:sub(first - 2, first - 2):match '^%x$')
    or (after == '-' and line:sub(last + 2, last + 2):match '^%x$')
  then
    return nil
  end
  return word, first, last
end

--- The link a hash under the cursor stands for, or nil. Only an org buffer:
--- nowhere else in the editor is a hex word a commit.
---@return table|nil link -- an org.Link
local function hash_link()
  if vim.bo.filetype ~= 'org' then
    return nil
  end
  local lnum, col = unpack(vim.api.nvim_win_get_cursor(0))
  local word, first, last = hash_at(vim.api.nvim_get_current_line(), col + 1)
  if not word then
    return nil
  end
  return {
    raw = word,
    target = 'git:' .. word,
    type = 'git',
    path = word,
    desc = word,
    lnum = lnum,
    end_lnum = lnum,
    start_col = first,
    end_col = last,
  }
end

--- The repos to look a hash up in, the ticket's own first: the directories
--- the entry's project claims, then the cwd, then the buffer's directory.
---@return string[] roots
local function roots()
  local seen, out = {}, {}
  local function add(dir)
    if not dir or dir == '' then
      return
    end
    local root = vim.fs.root(dir, '.git')
    if root and not seen[root] then
      seen[root] = true
      out[#out + 1] = root
    end
  end
  local file = vim.api.nvim_buf_get_name(0)
  local ok, project = pcall(require, 'helpers.org.project')
  if ok and file ~= '' then
    local ok_dirs, dirs = pcall(project.dirs, file, vim.api.nvim_win_get_cursor(0)[1])
    for _, dir in ipairs(ok_dirs and dirs or {}) do
      add(dir)
    end
  end
  add(vim.fn.getcwd())
  if file ~= '' then
    add(vim.fn.fnamemodify(file, ':p:h'))
  end
  return out
end

--- The full sha of `hash` and the repo that holds it, or nil.
---@param hash string
---@return string|nil sha
---@return string|nil root
function M.resolve(hash)
  for _, root in ipairs(roots()) do
    local res = vim.system({ 'git', '-C', root, 'rev-parse', '--verify', '--quiet', hash .. '^{commit}' }, { text = true }):wait()
    local sha = vim.trim(res.stdout or '')
    if res.code == 0 and sha ~= '' then
      return sha, root
    end
  end
  return nil, nil
end

--- Open `hash` as the diff of its commit -- the `git:` link type's follow, so
--- both a bare hash under the cursor and a written link land here.
---@param hash string
---@return boolean
function M.open(hash)
  hash = vim.trim(hash or '')
  local sha, root = M.resolve(hash)
  if not sha then
    require('org.utils').warn(string.format('No commit %q in this project\'s repos', hash))
    return false
  end
  -- `^!` is the commit against its parent: the change that commit made, not
  -- everything since. `-C` is diffview's cwd, so the repo holding the commit
  -- is read even from another project's board.
  local ok, err = pcall(function()
    require('diffview').open({ '-C' .. root, sha .. '^!' })
  end)
  if not ok then
    require('org.utils').error('Could not open the diff: ' .. tostring(err))
    return false
  end
  return true
end

function M.setup()
  -- The link is answered only once org.nvim's own module is there to wrap, so
  -- a hash never costs anything until a link is looked for the first time.
  require('org.lazy').on_load('org.links', 'commits_link', function(links)
    local at_cursor = links.link_at_cursor
    links.link_at_cursor = function()
      return at_cursor() or hash_link()
    end
  end)
end

return M
