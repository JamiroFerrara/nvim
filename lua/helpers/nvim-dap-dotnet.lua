-- lua/helpers/nvim-dap-dotnet.lua

--- Debug .NET projects with nvim-dap from *any* buffer inside the project.
---
--- The launch configuration is resolved from the buffer, never from its filetype:
--- the project root is found by walking up from the buffer directory (falling back
--- to the cwd tree when the buffer lives outside the project), the assembly is
--- picked from that project's `bin/<configuration>` output, and the session runs
--- with the project directory as cwd.
---
---   require('helpers.nvim-dap-dotnet').setup()   -- registers config + provider
---   M.project()                                  -- resolved project (root/dir/csproj/name)
---   M.build_dll_path()                           -- assembly to debug
---   M.working_dir()                              -- cwd for the debuggee

local M = {}

local uv = vim.uv or vim.loop

local DEFAULT_CONFIGURATION = 'Debug'

local DEFAULT_ENV = {
  ASPNETCORE_ENVIRONMENT = 'DEVE',
  ASPNETCORE_URLS = 'http://localhost:8000',
}

--- Directories never worth descending into while looking for project files.
local SKIP_DIRS = {
  ['bin'] = true,
  ['.git'] = true,
  ['.idea'] = true,
  ['node_modules'] = true,
  ['obj'] = true,
  ['packages'] = true,
  ['TestResults'] = true,
  ['.vs'] = true,
}

M.env = vim.deepcopy(DEFAULT_ENV)

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = 'nvim-dap-dotnet' })
end

local function fail(msg)
  notify(msg, vim.log.levels.ERROR)
  error(msg, 0)
end

local function is_file(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == 'file'
end

local function is_dir(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == 'directory'
end

--- Marker predicates for `vim.fs.root`/`vim.fs.find`. They must be functions:
--- string markers only match exact file names, not extensions.
local function is_csproj(name)
  return name:match '%.csproj$' ~= nil
end

local function is_sln(name)
  return name:match '%.slnx?$' ~= nil
end

local function project_name(csproj)
  return vim.fn.fnamemodify(csproj, ':t:r')
end

local function skip_dir(dir)
  return not SKIP_DIRS[vim.fs.basename(dir)]
end

local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return '' end
  return table.concat(lines, '\n')
end

--- Directory resolution starts from: the buffer's own directory when it is backed
--- by a file, the cwd for scratch/terminal/repl buffers.
---@param bufnr integer?
---@return string
function M.context_dir(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype == '' then
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= '' then return vim.fs.dirname(vim.fs.normalize(name)) end
  end
  return vim.fs.normalize(vim.fn.getcwd())
end

--- Last resort: look for a solution/project file *below* `dir`, for buffers that
--- live above their project tree (e.g. the repository root of a solution-less
--- repo). Shallowest marker wins, a `.sln` breaking ties.
local function search_down(dir, depth)
  local best
  for name, kind in vim.fs.dir(dir, { depth = depth, skip = skip_dir }) do
    if kind == 'file' and (is_sln(name) or is_csproj(name)) then
      local level = select(2, name:gsub('/', '/'))
      local shallower = not best or level < best.level
      if shallower or (level == best.level and is_sln(name) and not is_sln(best.name)) then best = { name = name, level = level } end
    end
  end
  return best and vim.fs.dirname(vim.fs.joinpath(dir, best.name)) or nil
end

--- Project root of `start`: nearest ancestor holding a `.csproj` or `.sln`, then
--- the cwd tree, then the enclosing git repository. Scoping the last resort to
--- the repository keeps the scan cheap and meaningful.
---@param start string?
---@return string? root
function M.find_root(start)
  start = start or M.context_dir()

  local root = vim.fs.root(start, { is_csproj, is_sln })
  if root then return root end

  local cwd = vim.fs.normalize(vim.fn.getcwd())
  if cwd ~= start then
    root = vim.fs.root(cwd, { is_csproj, is_sln })
    if root then return root end
  end

  local repo = vim.fs.root(start, '.git') or (cwd ~= start and vim.fs.root(cwd, '.git'))
  return repo and search_down(repo, 4) or nil
end

local function has_output_type(content)
  return content:match '<OutputType%s*>%s*Exe' ~= nil
end

local function is_test_project(csproj, content)
  if content:match '<IsTestProject%s*>%s*true' or content:match 'Microsoft%.NET%.Test%.Sdk' then return true end
  return project_name(csproj):match '%.Tests?$' ~= nil
end

local function is_runnable(csproj, content)
  if is_test_project(csproj, content) then return false end
  if has_output_type(content) then return true end
  if content:match 'Microsoft%.NET%.Sdk%.Web' or content:match 'Microsoft%.NET%.Sdk%.Worker' then return true end
  return is_file(vim.fs.joinpath(vim.fs.dirname(csproj), 'Program.cs'))
end

--- Candidate projects: those next to the root, else every project below it.
local function project_files(root)
  local direct = {}
  for name, kind in vim.fs.dir(root) do
    if kind == 'file' and is_csproj(name) then direct[#direct + 1] = vim.fs.joinpath(root, name) end
  end
  if #direct > 0 then
    table.sort(direct)
    return direct
  end

  local nested = {}
  for name, kind in vim.fs.dir(root, { depth = 8, skip = skip_dir }) do
    if kind == 'file' and is_csproj(name) then nested[#nested + 1] = vim.fs.joinpath(root, name) end
  end
  table.sort(nested)
  return nested
end

local function pick_project(candidates, root)
  if #candidates == 1 then return candidates[1] end

  local override = vim.g.dotnet_debug_project
  if override and override ~= '' then
    for _, csproj in ipairs(candidates) do
      if csproj == override or project_name(csproj) == override or vim.fs.basename(csproj) == override then return csproj end
    end
  end

  -- project named like the solution / root directory
  local wanted = vim.fs.basename(root):lower()
  for _, csproj in ipairs(candidates) do
    if project_name(csproj):lower() == wanted then return csproj end
  end

  local runnable = {}
  for _, csproj in ipairs(candidates) do
    if is_runnable(csproj, read(csproj)) then runnable[#runnable + 1] = csproj end
  end

  if #runnable == 0 then
    notify(string.format('No runnable project among %d under %s, using %s', #candidates, root, vim.fs.basename(candidates[1])), vim.log.levels.WARN)
    return candidates[1]
  end

  if #runnable > 1 then
    local names = {}
    for _, csproj in ipairs(runnable) do
      names[#names + 1] = project_name(csproj)
    end
    notify(
      string.format(
        '%d runnable projects under %s (%s), using %s. Set `vim.g.dotnet_debug_project` to pick another one.',
        #runnable,
        root,
        table.concat(names, ', '),
        project_name(runnable[1])
      ),
      vim.log.levels.WARN
    )
  end

  return runnable[1]
end

---@class DotnetProject
---@field root string    directory of the solution / project tree
---@field dir string     directory holding the chosen `.csproj`
---@field csproj string  path of the chosen `.csproj`
---@field name string    assembly name

--- Resolve the project the current (or given) buffer belongs to.
---@param start string? directory to resolve from, defaults to the current buffer
---@return DotnetProject?
function M.project(start)
  local root = M.find_root(start)
  if not root then return nil end

  local candidates = project_files(root)
  if #candidates == 0 then return nil end

  local csproj = pick_project(candidates, root)
  return {
    root = root,
    dir = vim.fs.dirname(csproj),
    csproj = csproj,
    name = project_name(csproj),
  }
end

local function declared_target_frameworks(csproj)
  local tfms = {}
  for list in read(csproj):gmatch '<TargetFrameworks?>%s*([^<]-)%s*</TargetFrameworks?>' do
    for tfm in list:gmatch '[^;%s]+' do
      tfms[#tfms + 1] = tfm
    end
  end
  return tfms
end

local function tfm_rank(tfm)
  local prefix, major, minor = tfm:match '^(%a+)(%d+)%.(%d+)'
  if not prefix then return { 0, 0, 0 } end
  local kind = prefix == 'net' and 2 or (prefix == 'netcoreapp' and 1 or 0)
  return { kind, tonumber(major), tonumber(minor) }
end

--- Newest target framework first (`net10.0` > `net8.0` > `netcoreapp3.1`).
local function sort_tfms(tfms)
  table.sort(tfms, function(a, b)
    local ra, rb = tfm_rank(a), tfm_rank(b)
    for i = 1, 3 do
      if ra[i] ~= rb[i] then return ra[i] > rb[i] end
    end
    return a < b
  end)
end

--- Assembly inside a target framework folder, either directly or under a
--- runtime identifier subfolder (`linux-x64`, `win-x64`, …).
local function dll_in(dir, name)
  local direct = vim.fs.joinpath(dir, name .. '.dll')
  if is_file(direct) then return direct end

  for entry, kind in vim.fs.dir(dir) do
    if kind == 'directory' then
      local nested = vim.fs.joinpath(dir, entry, name .. '.dll')
      if is_file(nested) then return nested end
    end
  end

  return nil
end

---@return string? dll, string? err
local function find_dll(project, configuration)
  local bin = vim.fs.joinpath(project.dir, 'bin', configuration)
  if not is_dir(bin) then
    return nil, string.format('No %s output for %s (expected %s). Run `dotnet build`.', configuration, project.name, bin)
  end

  local ordered, seen = {}, {}
  local function push(tfm)
    if not seen[tfm] then
      seen[tfm] = true
      ordered[#ordered + 1] = tfm
    end
  end

  -- declared target frameworks first, then whatever was actually built
  local declared = declared_target_frameworks(project.csproj)
  sort_tfms(declared)
  for _, tfm in ipairs(declared) do
    if is_dir(vim.fs.joinpath(bin, tfm)) then push(tfm) end
  end

  local built = {}
  for entry, kind in vim.fs.dir(bin) do
    if kind == 'directory' and entry:match '^net' then built[#built + 1] = entry end
  end
  sort_tfms(built)
  for _, tfm in ipairs(built) do
    push(tfm)
  end

  for _, tfm in ipairs(ordered) do
    local dll = dll_in(vim.fs.joinpath(bin, tfm), project.name)
    if dll then return dll end
  end

  -- custom OutputPath / unexpected layout
  local wanted = project.name .. '.dll'
  for entry, kind in vim.fs.dir(bin, { depth = 4, skip = skip_dir }) do
    if kind == 'file' and vim.fs.basename(entry) == wanted then return vim.fs.joinpath(bin, entry) end
  end

  return nil, string.format('No %s under %s. Run `dotnet build` for %s.', wanted, bin, vim.fs.basename(project.csproj))
end

--- Absolute path of the assembly to debug.
---@param opts? { start?: string, configuration?: string }
---@return string
function M.build_dll_path(opts)
  opts = opts or {}

  local project = M.project(opts.start)
  if not project then
    fail(string.format('No .NET project found from %s: no `.csproj` or `.sln` in its ancestors or below.', opts.start or M.context_dir()))
  end

  local dll, err = find_dll(project, opts.configuration or DEFAULT_CONFIGURATION)
  if not dll then fail(err) end

  print('dotnet-dap: launching ' .. dll)
  return dll
end

--- Directory the debuggee runs in: the project directory, so `appsettings.json`,
--- `wwwroot` and friends resolve independently of the file being edited.
---@return string
function M.working_dir()
  local project = M.project()
  return project and project.dir or vim.fs.normalize(vim.fn.getcwd())
end

---@return dap.Configuration[]
function M.configurations()
  return {
    {
      type = 'coreclr',
      request = 'launch',
      name = 'NetCoreDbg: Launch',
      program = function() return M.build_dll_path() end,
      cwd = function() return M.working_dir() end,
      env = M.env,
    },
  }
end

--- Register the .NET launch configuration with nvim-dap.
---
--- The configuration is served through a `dap.providers.configs` provider instead
--- of `dap.configurations.cs`, so `<F5>` starts the project's debug session from
--- any file inside the project (Razor, JSON, markdown, …) — and from the cwd when
--- the buffer is not inside the tree.
---@param opts? { env?: table<string, string> } overrides for the launch env
function M.setup(opts)
  opts = opts or {}
  M.env = vim.tbl_extend('force', vim.deepcopy(DEFAULT_ENV), opts.env or {})

  local dap = require 'dap'

  -- mason-nvim-dap installs `netcoredbg` and defines `coreclr` for us; keep the
  -- adapter working when netcoredbg is installed outside mason.
  if not dap.adapters.coreclr then
    local exe = vim.fn.exepath 'netcoredbg'
    if exe ~= '' then
      dap.adapters.coreclr = { type = 'executable', command = exe, args = { '--interpreter=vscode' } }
    else
      notify('`netcoredbg` not found, install it with `:MasonInstall netcoredbg`.', vim.log.levels.WARN)
    end
  end

  -- mason-nvim-dap also appends a generic coreclr entry to `dap.configurations.cs`
  -- (`fsharp`); drop it so the picker only offers the project-aware config.
  dap.configurations.cs = nil
  dap.configurations.fsharp = nil

  dap.providers.configs['nvim-dap-dotnet'] = function(bufnr)
    local filetype = vim.b[bufnr]['dap-srcft'] or vim.bo[bufnr].filetype
    local existing = dap.configurations[filetype]
    if existing and #existing > 0 then return {} end -- language has its own configurations

    if not M.find_root(M.context_dir(bufnr)) then return {} end
    return M.configurations()
  end
end

return M
