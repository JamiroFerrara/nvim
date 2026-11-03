-- The roam view in the editor: the knowledge base as a tree you walk in a
-- buffer, the way the TODO view walks the boards.
--
-- `7` in the agenda opens it for the cwd project's knowledge base -- the
-- documentation mirror of its board plus the topics those notes point at
-- (M.scope_file), the same scope the browser's roam page takes
-- (helpers/org/web/roam.lua) -- and `8` opens the whole vault: every note
-- below the roam directory. Both read the plugin's index through M.index, so a
-- note here is a note there: every file and every headline carrying an `:ID:`
-- is a node, and a link is the `id:` link the roam capture wrote.
--
-- A row is a note, nested the way its file nests it. Expanding a note also
-- lists the notes it links to (`→`) and the notes that link back (`←`), so
-- the graph is walked the way the tree is; a note already up the branch is
-- not entered again (`↻`), which is what keeps a cycle from ringing.
--
-- `<CR>` opens the note at its headline: a headline alone, in the entry
-- scratch helpers/org/entry.lua builds (`q` puts the view back), a file as
-- the file itself. <Tab> / `l` expand, <S-Tab> / `h` collapse, `R` reads the
-- vault again and redraws in place, `q` closes the view and puts the buffer
-- it replaced back.
--
-- The view is one of the boards' views, not a screen of its own: the agenda's
-- numbers mean here what they mean there (helpers.org.agenda's CUSTOM_VIEWS),
-- so `3` on this tree swaps the window to the board and `1` to the
-- cross-project list, while `7` and `8` pick the tree's own two scopes back up
-- -- the project's notes, or every note there is.
local M = {}

--- The roam extension's database, or nil when the extension is not
--- configured.
---@return table|nil
local function db()
  local ok, ext = pcall(require, 'org.extensions')
  if not ok then
    return nil
  end
  local ok_opts, opts = pcall(ext.opts, 'roam')
  if not ok_opts or not opts then
    return nil
  end
  local ok_db, roam_db = pcall(require, 'org.extensions.roam.db')
  return ok_db and roam_db or nil
end

--- The roam directory, or nil when the extension is not configured.
---@return string|nil
local function directory()
  local roam_db = db()
  if not roam_db then
    return nil
  end
  local ok, dir = pcall(roam_db.directory)
  return ok and dir or nil
end

--- The index walked once: nodes by id, the file-level node of every file, the
--- notes each note links to, the notes linking back, and the counts the rows
--- show.
---@return table|nil
local function walk()
  local roam_db = db()
  if not roam_db then
    return nil
  end
  if not pcall(roam_db.sync) then
    return nil
  end
  local nodes = roam_db.nodes() or {}
  local by_id, by_file = {}, {}
  for _, node in ipairs(nodes) do
    by_id[node.id] = node
    if node.level == 0 then
      by_file[node.file] = node
    end
  end
  -- one edge per pair: the graph is about notes, not about how many times one
  -- note says the other's name
  local edges, seen = {}, {}
  local outs, ins = {}, {}
  local outbound, inbound = {}, {}
  for _, link in ipairs(roam_db.links() or {}) do
    local target = link.type == 'id' and by_id[link.path] or nil
    if target and link.source and by_id[link.source] and target.id ~= link.source then
      local key = link.source .. '\0' .. target.id
      if not seen[key] then
        seen[key] = true
        edges[#edges + 1] = { source = link.source, target = target.id }
        outs[link.source] = outs[link.source] or {}
        table.insert(outs[link.source], target.id)
        ins[target.id] = ins[target.id] or {}
        table.insert(ins[target.id], link.source)
        outbound[link.source] = (outbound[link.source] or 0) + 1
        inbound[target.id] = (inbound[target.id] or 0) + 1
      end
    end
  end
  return {
    directory = roam_db.directory(),
    nodes = nodes,
    by_id = by_id,
    by_file = by_file,
    edges = edges,
    outs = outs,
    ins = ins,
    outbound = outbound,
    inbound = inbound,
  }
end

local cache = { at = 0, value = nil }

--- The walked index, cached for a moment so the view and a redraw do not sync
--- the directory twice, and so returning to the view after a jump does not
--- pay for a walk.
---@return table|nil
function M.index()
  local now = (vim.uv or vim.loop).hrtime() / 1e6
  if cache.value and now - cache.at < 1500 then
    return cache.value
  end
  local value = walk()
  if value then
    cache.value, cache.at = value, now
  end
  return value
end

--- Forget the walked index: the next M.index reads the vault again.
function M.invalidate()
  cache.value = nil
end

--- The file a project's knowledge base lives in: the roam directory's
--- `documentation/` mirror of the project's board (`~/org/projects/nvim.org`
--- -> `~/org/roam/documentation/nvim.org`), or `file` itself when it already
--- points inside the roam directory. Nil with no roam extension, or with no
--- `file`.
---@param file string|nil
---@return string|nil
function M.scope_file(file)
  local dir = directory()
  if not file or file == '' or not dir then
    return nil
  end
  local path = vim.fs.normalize(vim.fn.fnamemodify(file, ':p'))
  if vim.startswith(path, dir .. '/') then
    return path
  end
  return dir .. '/documentation/' .. vim.fs.basename(path)
end

--- Path of `path` from the home directory, the way the views name files.
---@param path string
---@return string
function M.relative(path)
  local home = vim.fs.normalize(vim.fn.expand '~')
  if vim.startswith(path, home .. '/') then
    return path:sub(#home + 2)
  end
  return path
end

local NS = vim.api.nvim_create_namespace 'org_roam_view'

--- The view: its buffer and window, the buffer it replaced, the tree it
--- draws, and which of its rows the reader has expanded.
local state = { buf = nil, win = nil, prev = nil, preview = nil, expanded = {}, rows = {}, prev_opts = {} }

--- Section titles for the roam directory's own folders, in the order the view
--- draws them; a folder this map does not name follows them, alphabetically.
local SECTIONS = { documentation = 'Documentation', topics = 'Topics', people = 'People', daily = 'Daily', playground = 'Playground' }
local SECTION_ORDER = { 'documentation', 'topics', 'people', 'daily', 'playground' }

--- Where a folder sits in the order above; an unnamed one comes last.
---@param name string
---@return integer
local function section_rank(name)
  for i, known in ipairs(SECTION_ORDER) do
    if known == name then
      return i
    end
  end
  return 1000
end

--- The row key of a note under `parent`: unique per branch, so two routes to
--- one note are two rows, each open or closed on its own.
---@param parent string
---@param relation string
---@param id string
---@return string
local function key_of(parent, relation, id)
  return parent .. '/' .. relation .. id
end

--- The key of the children a file node has in its own file.
---@param path string
---@return string
local function file_key(path)
  return '@file:' .. path
end

--- The folder of the vault's own layout a file sits in, from `dir`.
---@param path string
---@param dir string
---@return string
local function section_of(path, dir)
  if not vim.startswith(path, dir .. '/') then
    return 'other'
  end
  return (path:sub(#dir + 2):match '^([^/]+)/') or 'other'
end

--- The nodes each node has in its own file, by level, so the tree keeps the
--- file's own shape. A file's headline nodes hang under `file_key(path)`.
---@param idx table
---@return table<string, table[]>
local function structural_children(idx)
  local by_file_nodes = {}
  for _, node in ipairs(idx.nodes) do
    if node.level > 0 then
      by_file_nodes[node.file] = by_file_nodes[node.file] or {}
      table.insert(by_file_nodes[node.file], node)
    end
  end
  local children = {}
  for path, nodes in pairs(by_file_nodes) do
    table.sort(nodes, function(a, b)
      return a.lnum < b.lnum
    end)
    local stack = {}
    for _, node in ipairs(nodes) do
      while #stack > 0 and stack[#stack].level >= node.level do
        stack[#stack] = nil
      end
      local parent = stack[#stack]
      local key = parent and parent.id or file_key(path)
      children[key] = children[key] or {}
      table.insert(children[key], node)
      stack[#stack + 1] = node
    end
  end
  return children
end

--- The notes the tree hangs from: every file of the scope (one row each),
--- grouped by the folder of the vault's layout they sit in. A project's scope
--- keeps its own notes and the notes they link to, the browser's one hop out;
--- no scope keeps the whole vault.
---@param idx table
---@param scope string|nil
---@return table[] sections, table keep, integer edges
local function build(idx, scope)
  local keep -- nil keeps everything
  if scope then
    local own = {}
    for _, node in ipairs(idx.nodes) do
      if node.file == scope then
        own[node.id] = true
      end
    end
    keep = {}
    for id in pairs(own) do
      keep[id] = true
    end
    for _, edge in ipairs(idx.edges) do
      if own[edge.source] then
        keep[edge.target] = true
      end
    end
  end
  local files, count = {}, 0
  for _, node in ipairs(idx.nodes) do
    if not keep or keep[node.id] then
      files[node.file] = files[node.file] or {}
      table.insert(files[node.file], node)
      count = count + 1
    end
  end
  local links = 0
  for _, edge in ipairs(idx.edges) do
    if not keep or (keep[edge.source] and keep[edge.target]) then
      links = links + 1
    end
  end
  local sections = {}
  for path in pairs(files) do
    local name = section_of(path, idx.directory)
    sections[name] = sections[name] or { name = name, files = {}, notes = 0 }
    table.insert(sections[name].files, path)
    sections[name].notes = sections[name].notes + #files[path]
  end
  local out = {}
  for name, section in pairs(sections) do
    section.title = SECTIONS[name] or (name:sub(1, 1):upper() .. name:sub(2))
    table.sort(section.files)
    section.roots = {}
    for _, path in ipairs(section.files) do
      -- a mirror written without a file-level `:ID:` is no node, but its
      -- headlines still belong on screen: the file row is made for it
      local root = idx.by_file[path] or { id = file_key(path), file = path, level = 0, lnum = 1, title = vim.fs.basename(path):gsub('%.org$', '') }
      table.insert(section.roots, root)
    end
    out[#out + 1] = section
  end
  table.sort(out, function(a, b)
    local ar, br = section_rank(a.name), section_rank(b.name)
    if ar ~= br then
      return ar < br
    end
    return a.name < b.name
  end)
  return out, keep, links, count
end

--- The rows hanging below `node`: its own file's children first, then the
--- notes it links to, then the notes linking back to it.
---@param ctx table
---@param node table
---@return table[] { node, relation }
local function children_of(ctx, node)
  local out = {}
  local parent = node.level == 0 and file_key(node.file) or node.id
  for _, child in ipairs(ctx.children[parent] or {}) do
    out[#out + 1] = { node = child, relation = ' ' }
  end
  local function linked(list, relation)
    for _, id in ipairs(list or {}) do
      local target = ctx.idx.by_id[id]
      if target and (not ctx.keep or ctx.keep[id]) then
        out[#out + 1] = { node = target, relation = relation }
      end
    end
  end
  linked(ctx.idx.outs[node.id], '→')
  linked(ctx.idx.ins[node.id], '←')
  return out
end

--- Draw the tree into `lines`, one row per visible note. `ctx.rows` keeps
--- every drawn line's note, so the keys can act on the line under the cursor.
---@param ctx table
---@param lines string[]
---@param marks table[] { lnum, start, end, group }
local function draw(ctx, lines, marks)
  local function emit(node, relation, depth, parent, ancestors)
    local key = key_of(parent, relation, node.id)
    local kids = children_of(ctx, node)
    local repeat_of = ancestors[node.id]
    local branch = {}
    for id in pairs(ancestors) do
      branch[id] = true
    end
    branch[node.id] = true
    local expanded = not repeat_of and state.expanded[key] or false
    local marker
    if repeat_of then
      marker = '↻'
    elseif #kids > 0 then
      marker = expanded and '▾' or '▸'
    else
      marker = '·'
    end
    local title = (node.todo and (node.todo .. ' ') or '') .. (node.title or '')
    if repeat_of then
      title = title .. '  (already above)'
    end
    local prefix = string.rep('  ', depth)
    local line = prefix .. marker .. relation .. ' ' .. title
    local o, i = ctx.idx.outbound[node.id] or 0, ctx.idx.inbound[node.id] or 0
    local tail = {}
    if depth == 0 then
      tail[#tail + 1] = M.relative(node.file)
    end
    if o + i > 0 then
      tail[#tail + 1] = string.format('%d→ %d←', o, i)
    end
    local tail_text = #tail > 0 and ('  ' .. table.concat(tail, '  ')) or ''
    lines[#lines + 1] = line .. tail_text
    local lnum = #lines
    local marker_end = #prefix + #marker
    marks[#marks + 1] = { lnum, 0, #prefix, 'NonText' }
    if repeat_of then
      marks[#marks + 1] = { lnum, #prefix, marker_end, 'Comment' }
    end
    if relation ~= ' ' then
      marks[#marks + 1] = { lnum, marker_end, marker_end + #relation, 'Special' }
    end
    if #tail_text > 0 then
      marks[#marks + 1] = { lnum, #line, #line + #tail_text, 'Comment' }
    end
    ctx.rows[lnum] = { node = node, key = key, repeat_of = repeat_of and true or false }
    if expanded then
      for _, child in ipairs(kids) do
        emit(child.node, child.relation, depth + 1, key, branch)
      end
    end
  end
  local first = true
  for _, section in ipairs(ctx.sections) do
    if not first then
      lines[#lines + 1] = ''
    end
    first = false
    lines[#lines + 1] = string.format('%s  ·  %d note%s', section.title, section.notes, section.notes == 1 and '' or 's')
    marks[#marks + 1] = { #lines, 0, #lines[#lines], 'Title' }
    for _, root in ipairs(section.roots) do
      emit(root, ' ', 0, key_of('@section', ' ', section.name), {})
    end
  end
end

--- The row the cursor sits on, when it sits on a note of the view.
---@return table|nil row
local function row_at_cursor()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return nil
  end
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= state.buf then
    return nil
  end
  return state.rows[vim.api.nvim_win_get_cursor(win)[1]]
end

--- Draw the view again, keeping the cursor on `want`'s row when it is still
--- drawn.
---@param want string|nil
local function render(want)
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  local ctx = state.ctx
  local lines, marks = {}, {}
  state.rows = {}
  ctx.rows = state.rows
  if not ctx.idx then
    lines[1] = 'org-roam is not configured'
    marks[1] = { 1, 0, #lines[1], 'ErrorMsg' }
  elseif #ctx.sections == 0 then
    if ctx.scope then
      lines[1] = 'nothing in the knowledge base for ' .. ctx.name .. ' yet'
      lines[2] = '  ' .. M.relative(ctx.scope)
      lines[3] = '  seed it from the board: ~/org/scripts/roam-seed/seed.py --write'
      marks[1] = { 1, 0, #lines[1], 'Comment' }
      marks[2] = { 2, 0, #lines[2], 'Comment' }
      marks[3] = { 3, 0, #lines[3], 'Comment' }
    else
      lines[1] = 'nothing in the knowledge base yet'
      marks[1] = { 1, 0, #lines[1], 'Comment' }
    end
  else
    local title = 'Roam · ' .. ctx.name
    local stat = string.format('%d note%s · %d link%s', ctx.notes, ctx.notes == 1 and '' or 's', ctx.links, ctx.links == 1 and '' or 's')
    lines[#lines + 1] = title .. string.rep(' ', math.max(1, 60 - #title - #stat)) .. stat
    marks[#marks + 1] = { 1, 0, #title, 'Title' }
    marks[#marks + 1] = { 1, #lines[1] - #stat, #lines[1], 'Comment' }
    lines[#lines + 1] = string.rep('─', math.min(60, vim.o.columns - 1))
    marks[#marks + 1] = { 2, 0, #lines[2], 'NonText' }
    draw(ctx, lines, marks)
  end
  -- an unchanged tree is not rewritten: only a change has to be drawn, and
  -- setting the same lines again on every return to the view would move the
  -- cursor about for nothing
  local current = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  if not vim.deep_equal(current, lines) then
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
    for _, mark in ipairs(marks) do
      local text = lines[mark[1]]
      if text and mark[2] < mark[3] then
        vim.api.nvim_buf_set_extmark(state.buf, NS, mark[1] - 1, mark[2], {
          end_col = math.min(mark[3], #text),
          hl_group = mark[4],
          priority = 100,
        })
      end
    end
  end
  local win = state.win
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  local last = math.max(1, vim.api.nvim_buf_line_count(state.buf))
  local target
  if want then
    for lnum, row in pairs(state.rows) do
      if row.key == want then
        target = lnum
        break
      end
    end
  end
  if not target then
    for lnum in pairs(state.rows) do
      if not target or lnum < target then
        target = lnum
      end
    end
  end
  pcall(vim.api.nvim_win_set_cursor, win, { math.min(target or 1, last), 0 })
end

--- Read the vault again and draw it in place, keeping the cursor on the row
--- it was on.
function M.refresh()
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  local row = row_at_cursor()
  M.invalidate()
  local ctx = state.ctx
  ctx.idx = M.index()
  ctx.sections, ctx.keep, ctx.links, ctx.notes = build(ctx.idx, ctx.scope)
  ctx.children = ctx.idx and structural_children(ctx.idx) or {}
  render(row and row.key or nil)
end

--- The split the notes are read in, beside the tree: made when the first note
--- is opened, reused after that. Nil when the view's own window is gone.
---@return integer|nil
local function preview_win()
  local win = state.preview
  if win and vim.api.nvim_win_is_valid(win) then
    return win
  end
  local view = state.win
  if not (view and vim.api.nvim_win_is_valid(view)) then
    return nil
  end
  local new
  pcall(vim.api.nvim_win_call, view, function()
    vim.cmd 'botright vsplit'
    new = vim.api.nvim_get_current_win()
  end)
  if not new then
    return nil
  end
  pcall(vim.api.nvim_win_set_width, new, math.max(40, math.floor(vim.o.columns / 2)))
  vim.wo[new].wrap = true
  vim.wo[new].number = false
  vim.wo[new].relativenumber = false
  vim.wo[new].cursorline = false
  state.preview = new
  return new
end

--- Close the note split, if it is open.
local function close_preview()
  local win = state.preview
  state.preview = nil
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

--- Show the note on the row at the cursor beside the tree: a headline alone,
--- in the entry scratch helpers/org/entry.lua builds, a file as the file
--- itself. `q` in the split closes it and leaves the tree where it was.
local function preview_at_cursor()
  local row = row_at_cursor()
  local node = row and row.node
  if not node or not node.file then
    return
  end
  local win = preview_win()
  if not win then
    return
  end
  local buf = vim.fn.bufadd(node.file)
  vim.fn.bufload(buf)
  if node.level == 0 then
    vim.api.nvim_win_set_buf(win, buf)
    pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
  else
    require('helpers.org.entry').open(buf, node.lnum, { win = win })
  end
  vim.keymap.set('n', 'q', close_preview, { buffer = vim.api.nvim_win_get_buf(win), desc = 'roam: close the note' })
  vim.keymap.set('n', '<Esc>', close_preview, { buffer = vim.api.nvim_win_get_buf(win), desc = 'roam: close the note' })
  pcall(vim.api.nvim_set_current_win, state.win)
end

--- Expand or collapse the row at the cursor.
---@param open boolean
local function toggle(open)
  local row = row_at_cursor()
  if not row or row.repeat_of then
    return
  end
  state.expanded[row.key] = open or nil
  render(row.key)
end

--- Close the view, putting back the buffer it replaced.
function M.close()
  close_preview()
  local win = state.win
  if win and vim.api.nvim_win_is_valid(win) then
    for name, value in pairs(state.prev_opts or {}) do
      pcall(function()
        vim.wo[win][name] = value
      end)
    end
    if state.prev and vim.api.nvim_buf_is_valid(state.prev) then
      pcall(vim.api.nvim_win_set_buf, win, state.prev)
    else
      pcall(vim.api.nvim_win_call, win, function()
        vim.cmd 'enew'
      end)
    end
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state = { buf = nil, win = nil, prev = nil, preview = nil, expanded = {}, rows = {}, prev_opts = {} }
end

--- Open the roam view for `file`'s project, or for the whole vault when
--- `file` names no project.
---@param file string|nil
function M.open(file)
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    M.close()
  end
  local idx = M.index()
  local scope = file and file ~= '' and M.scope_file(file) or nil
  local name = scope and vim.fs.basename(scope):gsub('%.org$', '') or 'vault'
  local sections, keep, links, notes = {}, nil, 0, 0
  if idx then
    sections, keep, links, notes = build(idx, scope)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].undolevels = -1
  vim.bo[buf].filetype = 'orgroam'
  pcall(vim.api.nvim_buf_set_name, buf, 'roam://' .. name)
  local win = vim.api.nvim_get_current_win()
  state = {
    buf = buf,
    win = win,
    prev = vim.api.nvim_win_get_buf(win),
    preview = nil,
    prev_opts = { wrap = vim.wo[win].wrap, cursorline = vim.wo[win].cursorline },
    expanded = {},
    rows = {},
    ctx = {
      idx = idx,
      scope = scope,
      name = name,
      sections = sections or {},
      keep = keep,
      links = links or 0,
      notes = notes or 0,
      children = idx and structural_children(idx) or {},
    },
  }
  -- a project's own files start open, so the notes it knows are on screen
  -- when the view opens; every link stays folded until it is walked. The
  -- whole vault opens folded instead -- its tree is every note there is.
  if scope then
    for _, section in ipairs(state.ctx.sections) do
      for _, root in ipairs(section.roots) do
        state.expanded[key_of(key_of('@section', ' ', section.name), ' ', root.id)] = true
      end
    end
  end
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.keymap.set('n', 'q', M.close, { buffer = buf, desc = 'roam: close the view' })
  vim.keymap.set('n', '<Esc>', M.close, { buffer = buf, desc = 'roam: close the view' })
  vim.keymap.set('n', '<CR>', preview_at_cursor, { buffer = buf, desc = 'roam: read the note beside the tree' })
  vim.keymap.set('n', '<Tab>', function()
    toggle(true)
  end, { buffer = buf, desc = 'roam: expand the note' })
  vim.keymap.set('n', 'l', function()
    toggle(true)
  end, { buffer = buf, desc = 'roam: expand the note' })
  vim.keymap.set('n', '<S-Tab>', function()
    toggle(false)
  end, { buffer = buf, desc = 'roam: collapse the note' })
  vim.keymap.set('n', 'h', function()
    toggle(false)
  end, { buffer = buf, desc = 'roam: collapse the note' })
  vim.keymap.set('n', 'R', M.refresh, { buffer = buf, desc = 'roam: read the vault again' })
  -- the agenda's numbers mean the same views here: pressing `3` on the tree
  -- swaps the window over to the board, `1` to the cross-project list, while
  -- `7` and `8` are this view's two scopes -- the project's notes and the
  -- whole vault -- so one keyboard reaches every view whichever one is on
  -- screen
  for digit = 1, 6 do
    local key = tostring(digit)
    vim.keymap.set('n', key, function()
      M.close()
      require('helpers.org.agenda').digit(key)
    end, { buffer = buf, desc = 'roam: switch to view ' .. digit })
  end
  vim.keymap.set('n', '7', M.project, { buffer = buf, desc = 'roam: the cwd project knowledge base' })
  vim.keymap.set('n', '8', M.vault, { buffer = buf, desc = 'roam: the whole knowledge base' })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = close_preview,
    desc = 'roam: the note split goes with the view',
  })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
    buffer = buf,
    callback = function()
      if vim.api.nvim_get_current_buf() == buf then
        M.refresh()
      end
    end,
    desc = 'roam: follow the vault while the view is open',
  })
  render(nil)
end

--- `7`: the cwd project's knowledge base as a tree. Without a project, the
--- whole vault -- the view never narrows to another project's notes, so a cwd
--- that names nothing gets everything rather than an empty screen. Already on
--- the project's tree, the key reads it again instead of rebuilding it, so the
--- expanded notes stay open.
function M.project()
  local project = require('helpers.org.project').current()
  local scope = project and project.file and M.scope_file(project.file) or nil
  if state.ctx and state.ctx.scope == scope then
    return M.refresh()
  end
  M.open(project and project.file)
end

--- `8`: the whole knowledge base as a tree -- every note below the roam
--- directory, not just the cwd project's. Already on it, the key reads it
--- again.
function M.vault()
  if state.ctx and state.ctx.scope == nil then
    return M.refresh()
  end
  M.open(nil)
end

return M
