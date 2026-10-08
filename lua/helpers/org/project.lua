-- Working directory -> project for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua and the org symbol mappings).
--
-- A project's home is a file ~/org/projects/<name>.org or a headline inside
-- one. Both are claims over directories:
--   * `#+PROJECT_DIRS:` at file level claims for the whole file;
--   * `:PROJECT_DIRS:` in a headline's drawer claims for that headline, so
--     one file can host several projects (a client roll-up, a tangle, or
--     just a shared inbox).
-- The longest directory prefix covering the cwd wins; org nesting is
-- irrelevant, and on an equal-length tie a headline claim beats the file's
-- own. With no claim at all, the nearest ancestor holding a `.git` entry
-- names the project (a worktree resolves to its main repo, so its TODOs stay
-- in one file). Neither: no project, callers fall back to the picker.
--
-- The write side (`^` only) creates the file for a `.git`-derived project
-- and records the claim. Headlines are never created: a claim over a
-- headline that no longer exists is simply gone from the index, and the cwd
-- falls back to the next matching claim, the `.git` root, or the picker.
--
-- The resolution is per command (getcwd), never frozen at session start:
-- `cd` into another repo switches the project.
--
-- Two facts drive the details:
--   * the cwd is resolved through symlinks first: ~/.config/nvim is a
--     symlink to ~/dotfiles/nvim, and only the real path matches that
--     project's claim;
--   * `.git` may be a file (worktree/submodule), not just a directory.
local M = {}

local projects_dir = '~/org/projects'
local excluded_dirs = { '~/.config', '~/.cache', '/tmp' }

local index -- { { dir, file, name, olp?, line?, end_line? } }, rebuilt on change
local stamps = {}
local git_roots = {} -- cwd -> repo root, false when there is none
local warned = {}

local function once(key, msg)
  if not warned[key] then
    warned[key] = true
    require('org.utils').warn(msg)
  end
end

--- Absolute, slash-trimmed path for `~`/relative input.
---@param path string
---@return string
local function norm(path)
  local abs = vim.fn.fnamemodify(vim.fn.expand(path), ':p')
  return (vim.fs.normalize(abs):gsub('/+$', ''))
end

---@param dir string normalized directory
---@param path string normalized path
---@return boolean
local function is_under(dir, path)
  return path == dir or path:sub(1, #dir + 1) == dir .. '/'
end

--- Outline path from the file root down to `hl` (its plain titles).
---@param hl table
---@return string[]
local function olp_of(hl)
  local path, node = {}, hl
  while node do
    table.insert(path, 1, node:plain_title())
    node = node.parent
  end
  return path
end

--- Outline path of a file-level project: its first level-1 headline.
---@param file table|nil
---@return string[]|nil
local function file_olp(file)
  local first = file and file.children and file.children[1]
  if first then
    return { first:plain_title() }
  end
end

--- `#+PROJECT_DIRS:` / `:PROJECT_DIRS:` values, split like org's file list
--- (whitespace or commas).
---@param value string
---@return string[]
local function split_dirs(value)
  local out = {}
  for dir in value:gmatch '[^%s,]+' do
    out[#out + 1] = norm(dir)
  end
  return out
end

--- The claims a project file makes: its file-level keyword, then the
--- `:PROJECT_DIRS:` property of each headline.
---@param path string
---@return table[] { dir, olp?, line?, end_line? }
local function claims_of(path)
  local ok, file = pcall(function()
    return require('org.files').get(path)
  end)
  if not ok or not file then
    return {}
  end
  local out = {}
  local keywords = file.settings and file.settings.keywords
  for _, value in ipairs((keywords and keywords.PROJECT_DIRS) or {}) do
    for _, dir in ipairs(split_dirs(value)) do
      out[#out + 1] = { dir = dir, olp = file_olp(file) }
    end
  end
  for _, hl in ipairs(file.headlines or {}) do
    -- own property drawer only: a child headline must not inherit the claim
    local value = hl:get_property('PROJECT_DIRS', false)
    if value then
      local dirs = split_dirs(value)
      if #dirs == 0 then
        require('org.utils').warn(string.format('project: empty :PROJECT_DIRS: on %s line %d', vim.fn.fnamemodify(path, ':t'), hl.line))
      end
      for _, dir in ipairs(dirs) do
        out[#out + 1] = { dir = dir, olp = olp_of(hl), line = hl.line, end_line = hl.end_line, name = hl:plain_title() }
      end
    end
  end
  return out
end

local function stamp(path)
  local st = vim.uv.fs_stat(path)
  return st and (st.mtime.sec .. ':' .. st.size) or 'nil'
end

--- Rebuild the claim index when any project file changed (mtime or size, so
--- a rewrite that keeps the mtime on coarse file systems is still seen).
---@return boolean rebuilt
local function refresh()
  local paths = vim.fn.glob(vim.fn.expand(projects_dir) .. '/*.org', false, true)
  table.sort(paths)
  local fresh = {}
  local changed = #paths ~= vim.tbl_count(stamps)
  for _, p in ipairs(paths) do
    fresh[p] = stamp(p)
    if stamps[p] ~= fresh[p] then
      changed = true
    end
  end
  if not changed then
    return false
  end
  stamps = fresh
  index = {}
  git_roots = {}
  for _, p in ipairs(paths) do
    local base = vim.fn.fnamemodify(p, ':t:r')
    for _, claim in ipairs(claims_of(p)) do
      local node = claim.olp and claim.olp[#claim.olp]
      index[#index + 1] = {
        dir = claim.dir,
        file = p,
        name = claim.name or node or base,
        olp = claim.olp,
        line = claim.line,
        end_line = claim.end_line,
      }
    end
  end
  return true
end

--- Longest claim covering `cwd`; a headline claim wins an equal-length tie
--- against a file claim, and different files claiming the same dirs warn.
---@param cwd string normalized
---@return table|nil { dir, file, name, olp?, line?, end_line? }
local function best_claim(cwd)
  refresh()
  local best
  for _, e in ipairs(index) do
    if is_under(e.dir, cwd) then
      if not best or #e.dir > #best.dir then
        best = e
      elseif #e.dir == #best.dir and e.line and not best.line then
        best = e
      elseif #e.dir == #best.dir and best.file ~= e.file then
        once(
          'tie:' .. e.dir,
          string.format('project: %s claims %s like %s, using the first', vim.fn.fnamemodify(e.file, ':t'), e.dir, vim.fn.fnamemodify(best.file, ':t'))
        )
      end
    end
  end
  return best
end

--- Root of the main repo of `dir`, when `.git` is a file (worktree or
--- submodule): `--git-common-dir` is the main `.git`, its parent the root.
--- Nil keeps the worktree's own directory.
---@param dir string
---@return string|nil
local function main_repo(dir)
  local ok, out = pcall(vim.fn.systemlist, { 'git', '-C', dir, 'rev-parse', '--path-format=absolute', '--git-common-dir' })
  if not ok or vim.v.shell_error ~= 0 or not out or not out[1] or out[1] == '' then
    return nil
  end
  local common = out[1]
  if common:sub(1, 1) ~= '/' then
    common = dir .. '/' .. common
  end
  common = norm(common)
  local worktrees = common:match '^(.*)/%.git/worktrees/[^/]+$'
  if worktrees then
    return worktrees
  end
  if common:sub(-5) == '/.git' then
    return norm(vim.fn.fnamemodify(common, ':h'))
  end
  return nil
end

--- Nearest ancestor of `cwd` with a `.git` entry.
---@param cwd string normalized
---@return string|nil
local function git_root(cwd)
  local cached = git_roots[cwd]
  if cached ~= nil then
    return cached or nil
  end
  local dir, found = cwd, nil
  while dir and dir ~= '' and dir ~= '/' do
    local st = vim.uv.fs_stat(dir .. '/.git')
    if st then
      found = dir
      if st.type == 'file' then
        found = main_repo(dir) or dir
      end
      break
    end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then
      break
    end
    dir = parent
  end
  git_roots[cwd] = found or false
  return found
end

---@param cwd string normalized
---@return boolean
local function excluded(cwd)
  if cwd == norm '~' then
    return true
  end
  for _, dir in ipairs(excluded_dirs) do
    if is_under(norm(dir), cwd) then
      return true
    end
  end
  return false
end

--- Directory the current command reads: a terminal buffer resolves to the
--- working directory of the shell running in it (`cd` inside the terminal
--- counts, which is what a capture started there should file against),
--- anything else to nvim's own cwd.
---@return string
local function base_dir()
  local buf = vim.api.nvim_get_current_buf()
  local job = vim.bo[buf].buftype == 'terminal' and vim.b[buf].terminal_job_id or nil
  local pid = job and vim.fn.jobpid(job) or nil
  if pid and pid > 0 then
    local ok, cwd = pcall(vim.uv.fs_readlink, '/proc/' .. pid .. '/cwd')
    if ok and cwd then
      return cwd
    end
  end
  return vim.fn.getcwd()
end

--- Warn when a claim is so broad it swallows an excluded directory (~ and
--- friends): every cwd below it then resolves to that one project.
---@param claim table
local function warn_broad(claim)
  local dirs = { norm '~' }
  vim.list_extend(dirs, vim.tbl_map(norm, excluded_dirs))
  for _, dir in ipairs(dirs) do
    if is_under(claim.dir, dir) then
      once(
        'broad:' .. claim.file .. claim.dir,
        string.format(
          'project: %s claims %s, which covers %s -- every directory below it resolves to this file',
          vim.fn.fnamemodify(claim.file, ':t'),
          claim.dir,
          dir
        )
      )
      return
    end
  end
end

--- The project the cwd belongs to.
---@return table|nil { name, file, dir?, olp?, line?, end_line?, root?, source = 'claim'|'git' }
function M.current()
  local base = base_dir()
  local cwd = norm(vim.uv.fs_realpath(base) or base)
  if excluded(cwd) then
    return nil
  end
  local claim = best_claim(cwd)
  if claim then
    warn_broad(claim)
    return {
      name = claim.name,
      file = claim.file,
      dir = claim.dir,
      olp = claim.olp,
      line = claim.line,
      end_line = claim.end_line,
      source = 'claim',
    }
  end
  local root = git_root(cwd)
  if not root then
    return nil
  end
  local name = vim.fn.fnamemodify(root, ':t')
  if name == '' then
    return nil
  end
  return { name = name, file = norm(projects_dir .. '/' .. name .. '.org'), root = root, source = 'git' }
end

--- Display name of `project`: a headline claim keeps its headline title, a
--- file project uses its level-1 headline when it has one.
---@param project table
---@return string
function M.title(project)
  if project.line then
    return project.name
  end
  if vim.uv.fs_stat(project.file) then
    local ok, file = pcall(function()
      return require('org.files').get(project.file)
    end)
    local first = ok and file and file.children and file.children[1]
    if first then
      return first:plain_title()
    end
  end
  return project.name
end

--- Outline path the capture for `project` lands under. Both branches rely on
--- the node existing: a `.git`-derived file is written with its level-1
--- headline by `ensure`, and a headline claim resolves exactly.
---@param project table
---@return string[]
function M.olp(project)
  if project.line then
    return project.olp
  end
  return { M.title(project) }
end

--- Agenda restriction narrowing the project to its subtree, for a headline
--- claim. Nil for a file project, whose TODOs are the whole file.
---@param project table
---@return table|nil { filename, range }
function M.restrict(project)
  if not project.line then
    return nil
  end
  return { filename = project.file, range = { project.line, project.end_line } }
end

--- The files a project's TODOs live in.
---@param project table
---@return string[]
function M.files(project)
  return { project.file }
end

--- Write side (`^` only): create the file for a `.git`-derived project, or
--- record an extra directory when a second repo of the same basename landed
--- on an existing file. Headline claims are never created. Returns false
--- when the file cannot be created.
---@param project table
---@return boolean
function M.ensure(project)
  if project.source ~= 'git' then
    return true
  end
  vim.fn.mkdir(vim.fn.expand(projects_dir), 'p')
  if vim.uv.fs_stat(project.file) then
    local claimed = false
    for _, claim in ipairs(claims_of(project.file)) do
      if claim.dir == project.root then
        claimed = true
        break
      end
    end
    if not claimed then
      local ok, lines = pcall(vim.fn.readfile, project.file)
      if ok and #lines > 0 then
        table.insert(lines, 1, '#+PROJECT_DIRS: ' .. project.root)
        if not pcall(vim.fn.writefile, lines, project.file) then
          return false
        end
        require('org.files').invalidate(project.file)
        refresh()
        once('merge:' .. project.file, string.format('project: %s also covers %s', vim.fn.fnamemodify(project.file, ':t'), project.root))
      end
    end
    return true
  end
  local lines = { '#+PROJECT_DIRS: ' .. project.root, '', '* ' .. project.name }
  if not pcall(vim.fn.writefile, lines, project.file) then
    require('org.utils').warn('project: cannot write ' .. project.file)
    return false
  end
  require('org.files').invalidate(project.file)
  refresh()
  once('created:' .. project.file, 'project: created ' .. vim.fn.fnamemodify(project.file, ':t'))
  return true
end

--- The `°` view: the open TODOs of the current project, or of every agenda
--- file when the cwd has no project. A headline project is restricted to its
--- subtree. The view takes over the focused window (agenda.window =
--- 'current' in the plugin spec) rather than splitting below it; `q` puts
--- the buffer back.
function M.todo_view()
  local utils = require 'org.utils'
  utils.run(function()
    local project = M.current()
    local spec, opts
    if project and vim.uv.fs_stat(project.file) then
      spec = { type = 'todo', files = M.files(project), description = 'TODO: ' .. M.title(project) }
      local restrict = M.restrict(project)
      if restrict then
        opts = { restrict = restrict }
      end
    else
      spec = { type = 'todo', description = 'TODO' }
    end
    require('org.agenda').open(spec, opts)
  end)
end

return M
