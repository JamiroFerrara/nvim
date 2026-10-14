-- Subtrees in the TODO views (wired in lua/terminal_plugins/org.nvim.lua).
--
-- A TODO view -- the `o` list, the board (digit 3 / `°`, and the digit-2
-- group view over a whole file), anything rendering a `todo`, `tags_todo`
-- or `search` block -- shows an entry's sublevels as a tree, folded at level
-- 1, matching the org file. `agenda.todo_list_sublevels`
-- / `tags_match_list_sublevels` are off (lua/terminal_plugins/org.nvim.lua),
-- so org.nvim lists only the top-level entries; this helper adds the
-- subheadlines back, under their ancestor:
--
--   * it wraps `org.agenda.render.view` and, once the view is built --
--     groups, section rules and all -- reorders the item lines of every
--     contiguous run into tree order: a listed ancestor's children follow
--     it, depth-first, siblings keeping the agenda's sort order. Runs are
--     what the grouper left between its headers, so nesting never crosses a
--     category heading or a board section;
--   * a TODO nested under another TODO -- a subtask -- never shows as a line
--     of its own: its listed line is dropped from whatever block matched it
--     (so a sub-task does not surface at the top level of a section its
--     ancestor is not in) and it reappears, folded, under the ancestor. The
--     view's first level is always the top-level entries;
--   * it adds the plain (not TODO) subheadlines of a listed entry as their
--     own lines, rendered like any entry (`org.agenda.render.item_line`), so
--     a subtree shows whole; a subheadline that is itself a listed entry
--     keeps its agenda unit, and its own subtree is not repeated under the
--     ancestor;
--   * a child line drops the agenda prefix (category, date): its text --
--     keyword, priority, title, tags -- starts at its ancestor's content
--     column, one tree level in, after the box-drawing guides (`├─ `, `└─ `,
--     `│  `); it re-attributes the view's line tables (`lines`, `hls`,
--     `items`, `line_hls`, `line_ctx`, `entry_text_lines`, `day_lines`,
--     `super_headers`, `block_starts`) to the new rows, so the entry at the
--     cursor is still the entry org.nvim thinks it is;
--   * it folds at level 1: a node starts folded, so only the entries with no
--     listed parent show, and a node's line carries the size of its subtree,
--     `… (N)` with the `…` while descendants are hidden and plain `(N)`
--     once they are shown;
--   * `<Tab>` is fold-only in the view: it cycles the node at point
--     (folded -> children -> subtree -> folded), like org's own <Tab>. On a
--     line without a subtree it falls back to the group header's own fold
--     (org-super-agenda's `toggle_group`, which this key would otherwise
--     shadow) -- never to org.nvim's `goto`, which opened the entry's source
--     file in a split (`<Space>` / `o` / `<CR>` are what leave the view);
--     `<S-Tab>` cycles every node of the view;
--   * `l` unfolds what is folded at point, one direction only: the node's
--     subtree in a TODO view (one step: folded -> children -> subtree), a
--     folded group header (`… (N)`) in any agenda view. It takes the key
--     from log mode, which keeps its `vl` spelling;
--   * `c` (and its longer spelling `<leader>aC`) captures a new entry as a
--     child of the entry at point, by pointing the Task template at the
--     entry's own outline path -- the agenda's default `c`
--     (org-agenda-calendar) is unbound in the plugin spec to give it the
--     key;
--   * it highlights the statistics cookies (`[1/3]`, `[50%]`) of the view's
--     entry lines, as an org buffer does through treesitter.
--
-- Expansion state is keyed by the entry (file, line, and the title with its
-- statistics cookie dropped), so it survives the re-render every remote edit
-- triggers -- including a state change, which rewrites an ancestor's cookie.
-- Nothing here touches a day/week agenda view: a view with an `agenda` block
-- is left alone, so the date grid keeps its layout.
local M = {}

-- entry key -> "folded" | "children" | "subtree"
local states = {}
-- view -> tree of the last render; weak, the view object is rebuilt per open
local views = setmetatable({}, { __mode = 'k' })
-- buffer -> { [lnum] = super-agenda group id } of the last render: what a
-- group header line draws, for `l` to unfold it (the extension exports the
-- fold state of an id, not the header line -> id map).
local group_of = {}

local MODE_NEXT = { folded = 'children', children = 'subtree', subtree = 'folded' }
local HINT = 'OrgTreeFolded'

--- The identity a node's fold state is kept under: file, line, and the
--- title without its statistics cookie. A child's state change rewrites the
--- cookie in an ancestor's headline (`[0/2]` -> `[1/2]`), and the raw
--- headline would then read as a different entry and drop the fold state.
local function key_of(item)
  local title = item.title or item.raw or ''
  title = title:gsub('%s*%[%d*/%d*%]', ''):gsub('%s*%[%d*%%%]', '')
  return (item.filename or tostring(item.bufnr)) .. ':' .. tostring(item.lnum) .. ':' .. vim.trim(title)
end

local function is_todo_view(view)
  if not view then
    return false
  end
  for _, block in ipairs(view.blocks or {}) do
    if block.type == 'agenda' then
      return false
    end
  end
  return true
end

--- File `a`'s item belongs to (a path, else the buffer number). Headlines
--- carry their file; the item is the fallback for a headline without one.
local function file_of(nd)
  local f = nd.headline and nd.headline.file
  return f or nd.item.filename or nd.item.bufnr
end

--- `a`'s headline contains `b`'s (same file, b deeper).
local function is_ancestor(a, b)
  local ha, hb = a.headline, b.headline
  if not (ha and hb) or file_of(a) ~= file_of(b) then
    return false
  end
  return ha.line < hb.line and hb.line <= ha.end_line
end

---------------------------------------------------------------------------
-- The tree of one run
---------------------------------------------------------------------------

--- Node table for the units of one run, in agenda order. `units` is a list
--- of `{ item, rows }` (an item line plus the entry-text lines under it).
local function build_nodes(units)
  local nodes = {}
  for i, u in ipairs(units) do
    nodes[i] = { unit = u, item = u.item, headline = u.item.headline, children = {}, order = i }
  end
  for i, nd in ipairs(nodes) do
    local best
    for j, other in ipairs(nodes) do
      if i ~= j and is_ancestor(other, nd) then
        if not best or other.headline.line > best.headline.line then
          best = other
        end
      end
    end
    nd.parent = best
    if best then
      best.children[#best.children + 1] = nd
    end
  end
  local roots = {}
  for _, nd in ipairs(nodes) do
    local depth, p = 1, nd.parent
    while p do
      depth = depth + 1
      p = p.parent
    end
    nd.depth = depth
    nd.key = key_of(nd.item)
    nd.state = states[nd.key] or 'folded'
    if not nd.parent then
      roots[#roots + 1] = nd
    end
  end
  return nodes, roots
end

--- A node is visible when no ancestor is folded; an ancestor in the
--- "subtree" state (org's SHOW ALL) shows everything below it, and an
--- ancestor in the "children" state shows the node only if the ancestor is
--- itself visible -- the node's own parent governs the next level down.
local function visible(nd)
  local p = nd.parent
  while p do
    if p.state == 'subtree' then
      return true
    elseif p.state == 'folded' then
      return false
    end
    p = p.parent
  end
  return true
end

local function count_desc(nd)
  local n = #nd.children
  for _, ch in ipairs(nd.children) do
    n = n + count_desc(ch)
  end
  return n
end

--- Descendants of `nd` its state keeps off screen.
local function hidden_desc(nd)
  local n = 0
  for _, ch in ipairs(nd.children) do
    if visible(ch) then
      n = n + hidden_desc(ch)
    else
      n = n + 1 + count_desc(ch)
    end
  end
  return n
end

local function pad(width)
  return string.rep(' ', width)
end

---------------------------------------------------------------------------
-- Rewriting the builder
---------------------------------------------------------------------------

--- Emit the view's lines in `order`: a list of entries, each one either a
--- builder row (`{ row = n }`) or a line the builder does not have
--- (`{ text, hls, item }` -- a listed entry's plain subheadline).
--- `prefix`/`suffix` wrap the entry's line (tree guide, hidden-count hint);
--- every line-keyed table of the builder is re-attributed to the new rows.
local function reorder(b, order, old_n)
  local by_row = {}
  for _, h in ipairs(b.hls) do
    local list = by_row[h[1]]
    if not list then
      list = {}
      by_row[h[1]] = list
    end
    list[#list + 1] = h
  end
  local lines, hls = {}, {}
  local items, line_hls, line_ctx = {}, {}, {}
  local entry_text_lines, day_lines, super_headers = {}, {}, {}
  local map = {}
  for new, e in ipairs(order) do
    local prefix, suffix = e.prefix or '', e.suffix or ''
    local old = e.row
    local line = e.text or b.lines[old]
    local text_hls, item, line_hl = e.hls, e.item, e.line_hl
    if old then
      text_hls, item, line_hl = by_row[old - 1], b.items[old], b.line_hls[old]
      map[old] = new
    end
    local text = prefix .. line .. suffix
    lines[new] = text
    for _, h in ipairs(text_hls or {}) do
      -- a builder line's hls are `{ row, start, end, group, priority }`; the
      -- hls of a synthetic line (org.agenda.render.item_line) are
      -- `{ start, end, group }`
      local start, stop, group, prio = h[1], h[2], h[3], h[4]
      if old then
        start, stop, group, prio = h[2], h[3], h[4], h[5]
      end
      hls[#hls + 1] = { new - 1, start + #prefix, stop + #prefix, group, prio }
    end
    if suffix ~= '' then
      hls[#hls + 1] = { new - 1, #prefix + #line, #text, HINT }
    end
    if item then
      items[new] = item
    end
    if line_hl then
      line_hls[new] = line_hl
    end
    if old then
      if b.line_ctx and b.line_ctx[old] then
        line_ctx[new] = b.line_ctx[old]
      end
      if b.entry_text_lines and b.entry_text_lines[old] then
        entry_text_lines[new] = true
      end
      if b.day_lines and b.day_lines[old] then
        day_lines[new] = b.day_lines[old]
      end
      if b.super_headers and b.super_headers[old] then
        super_headers[new] = b.super_headers[old]
      end
    end
  end
  local new_n = #lines
  b.lines, b.hls = lines, hls
  b.items, b.line_hls = items, line_hls
  b.line_ctx, b.entry_text_lines = line_ctx, entry_text_lines
  b.day_lines, b.super_headers = day_lines, super_headers
  for i, s in ipairs(b.block_starts or {}) do
    local n = map[s]
    if not n then
      for k = s + 1, old_n do
        if map[k] then
          n = map[k]
          break
        end
      end
    end
    b.block_starts[i] = n or (new_n + 1)
  end
  return map
end

---------------------------------------------------------------------------
-- The render hook
---------------------------------------------------------------------------

local function transform(view, b, render, ctx)
  local items = b.items
  if not items or not next(items) then
    return nil
  end
  local n = #b.lines

  -- A TODO nested under another TODO is a subtask: by default it never shows
  -- as a line of its own (org.nvim lists such sublevels flat, once per block
  -- that matches them), it shows folded under its ancestor's line. `hidden`
  -- marks those listed lines so the run drops them; plain_children then
  -- re-adds each under its ancestor (an unlisted headline is a child there).
  local hidden = {}
  local function is_subtask(hl)
    local p = hl and hl.parent
    while p do
      if p.todo then
        return true
      end
      p = p.parent
    end
    return false
  end
  for l, item in pairs(items) do
    if is_subtask(item.headline) then
      hidden[l] = true
    end
  end

  -- lines the view already lists, per file: a subheadline that is itself a
  -- listed entry stays where the agenda put it, never a synthetic child. A
  -- hidden subtask is left out, so plain_children picks it up under its
  -- ancestor instead.
  local listed = {}
  for l, item in pairs(items) do
    local hl = item.headline
    if hl and item.filename and not hidden[l] then
      local set = listed[item.filename]
      if not set then
        set = {}
        listed[item.filename] = set
      end
      set[hl.line] = true
    end
  end

  --- Headlines of `item`'s own subtree the view does not list: the plain
  --- (not TODO) subheadlines org.nvim never feeds an agenda. A listed entry
  --- still shows its whole subtree, as an org file does; a listed
  --- subheadline's own subtree is left to its own unit, not repeated here.
  local function plain_children(item)
    local hl = item.headline
    local file = hl and hl.file
    if type(file) == 'string' then
      file = require('org.files').get(file)
    end
    local all = file and file.headlines
    if not all or not hl.end_line or hl.end_line <= hl.line then
      return nil
    end
    local set = listed[item.filename]
    local out, stop
    for _, h in ipairs(all) do
      if h.line > hl.end_line then
        break
      elseif h.line <= hl.line then -- an ancestor, or the entry itself
      elseif stop and h.line <= stop then -- inside a listed entry's subtree
      elseif set and set[h.line] then
        stop = h.end_line
      else
        out = out or {}
        out[#out + 1] = h
      end
    end
    return out
  end

  local new_item = require('org.agenda.items').new_item
  --- A line the builder does not have, rendered as an entry would be: the
  --- render context of the entry it hangs under (`b.line_ctx`), so a child
  --- line is drawn in its block's own style (kind, width).
  local function plain_unit(hl, c)
    local item = new_item(hl, { type = 'todo', ts_type = 'todo' })
    local text, hls, line_hl = render.item_line(item, c or ctx)
    if not text then
      return nil
    end
    return {
      item = item,
      ctx = c,
      rows = { { text = text, hls = hls, item = item, line_hl = line_hl } },
    }
  end

  -- units: an item line with the entry-text lines that follow it, plus a
  -- line per plain subheadline of the entry; every other line is a break
  -- between runs
  local units = {}
  local l = 1
  while l <= n do
    if items[l] and not hidden[l] then
      local u = { item = items[l], rows = { l }, ctx = b.line_ctx and b.line_ctx[l] }
      local k = l + 1
      while k <= n and b.entry_text_lines and b.entry_text_lines[k] do
        u.rows[#u.rows + 1] = k
        k = k + 1
      end
      units[#units + 1] = u
      for _, h in ipairs(plain_children(items[l]) or {}) do
        local cu = plain_unit(h, u.ctx)
        if cu then
          units[#units + 1] = cu
        end
      end
      l = k
    elseif items[l] then
      -- a hidden subtask (and its body): dropped here, plain_children
      -- re-added it under its ancestor's unit
      local k = l + 1
      while k <= n and b.entry_text_lines and b.entry_text_lines[k] do
        k = k + 1
      end
      l = k
    else
      units[#units + 1] = { sep = true, rows = { l } }
      l = l + 1
    end
  end

  --- An entry of `order` for one line of a unit (a builder row, else the
  --- synthetic line itself, copied as it is given a prefix).
  local function entry_of(r)
    return type(r) == 'number' and { row = r } or vim.deepcopy(r)
  end

  local order = {}
  local all, roots = {}, {}
  local tree_built = false
  local run = {}
  local function flush()
    if #run < 2 then
      for _, u in ipairs(run) do
        for _, r in ipairs(u.rows) do
          order[#order + 1] = entry_of(r)
        end
      end
      run = {}
      return
    end
    local nodes, run_roots = build_nodes(run)
    local has_child = false
    for _, nd in ipairs(nodes) do
      all[#all + 1] = nd
      if nd.parent then
        has_child = true
      end
    end
    vim.list_extend(roots, run_roots)
    if not has_child then
      for _, u in ipairs(run) do
        for _, r in ipairs(u.rows) do
          order[#order + 1] = entry_of(r)
        end
      end
      run = {}
      return
    end
    tree_built = true

    --- An item's line without the agenda prefix (category, date): the
    --- keyword/priority/title/tags columns, for a child line that is nested
    --- under an ancestor rather than listed on its own.
    local function no_prefix(nd)
      local c = nd.unit.ctx or ctx
      local kind = c.kind or (c.agenda and 'agenda' or 'todo')
      local text, hls = render.line_text(render.item_parts(nd.item, c))
      local cut = #render.prefix(nd.item, kind)
      if cut <= 0 or #text <= cut then
        return text, hls
      end
      local out, nh = text:sub(cut + 1), {}
      for _, h in ipairs(hls) do
        if h[2] > cut then
          nh[#nh + 1] = { math.max(h[1] - cut, 0), h[2] - cut, h[3], h[4] }
        end
      end
      return out, nh
    end

    --- `base` is the root's content column (its agenda prefix width); a
    --- child's text starts there, one `guide` (and `bars`) deeper, with no
    --- agenda prefix of its own.
    local function walk(nd, base, guide, bars)
      if not visible(nd) then
        return
      end
      local total = #nd.children > 0 and count_desc(nd) or 0
      local off = total > 0 and hidden_desc(nd) or 0
      local suffix = total > 0 and ((off > 0 and ' … (' or ' (') .. total .. ')') or ''
      if nd.parent then
        local text, hls = no_prefix(nd)
        local lead = pad(base) .. guide
        local shifted = {}
        for _, h in ipairs(hls) do
          shifted[#shifted + 1] = { h[1] + #lead, h[2] + #lead, h[3], h[4] }
        end
        order[#order + 1] = { text = lead .. text, hls = shifted, item = nd.item, suffix = suffix }
        nd.row = #order
      else
        for i, r in ipairs(nd.unit.rows) do
          local e = entry_of(r)
          e.prefix = ''
          e.suffix = i == 1 and suffix or ''
          order[#order + 1] = e
          if i == 1 then
            nd.row = #order
          end
        end
      end
      for i, ch in ipairs(nd.children) do
        local last = i == #nd.children
        walk(ch, base, bars .. (last and '└─ ' or '├─ '), bars .. (last and '   ' or '│  '))
      end
    end
    for _, nd in ipairs(run_roots) do
      local c = nd.unit.ctx or ctx
      local kind = c.kind or (c.agenda and 'agenda' or 'todo')
      local prefix = render.prefix(nd.item, kind)
      walk(nd, vim.fn.strdisplaywidth(prefix), '', '')
    end
    run = {}
  end
  for _, u in ipairs(units) do
    if u.sep then
      flush()
      for _, r in ipairs(u.rows) do
        order[#order + 1] = entry_of(r)
      end
    else
      run[#run + 1] = u
    end
  end
  flush()

  if not tree_built and not next(hidden) then
    return nil
  end
  reorder(b, order, n)
  local by_line = {}
  for _, nd in ipairs(all) do
    if nd.row then
      by_line[nd.row] = nd
    end
  end
  return { roots = roots, nodes = all, by_line = by_line }
end

local function setup_render()
  require('org.lazy').on_load('org.agenda.render', 'view_tree', function(render)
    if not render.view then
      return
    end
    local view = render.view
    render.view = function(v, ctx)
      local b = view(v, ctx)
      if b and is_todo_view(v) then
        local ok, tree = pcall(transform, v, b, render, ctx)
        if ok and tree then
          views[v] = tree
          b.tree = tree
        elseif not ok then
          require('org.utils').error('org tree: ' .. tostring(tree))
        end
      end
      return b
    end
  end)
end

---------------------------------------------------------------------------
-- Buffer keys
---------------------------------------------------------------------------

local function tree_of(buf)
  local state = require('org.agenda.view').state_of(buf)
  return state and state.view and views[state.view]
end

local function node_at(buf, lnum)
  local tree = tree_of(buf)
  return tree and tree.by_line[lnum]
end

--- Put the cursor back on the entry with `key` after a re-render.
local function refocus(buf, key)
  local view = require 'org.agenda.view'
  view.refresh()
  local state = view.state_of(buf)
  for lnum, item in pairs((state and state.line_items) or {}) do
    if key_of(item) == key then
      pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
      return
    end
  end
  local tree = tree_of(buf)
  if tree and tree.by_line then
    for lnum in pairs(tree.by_line) do
      pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
      return
    end
  end
end

local function cycle_node(buf, nd)
  local key = nd.key
  states[key] = MODE_NEXT[states[key] or nd.state or 'folded']
  refocus(buf, key)
end

--- The fold state of the group whose header line is `lnum`: `"folded"` /
--- `"shown"`, else nil when the line is not a group header (the `… (N)` on
--- the header shows a folded one). org-super-agenda exports the state of a
--- group id but keeps the line -> id map private, and `group_of` is that
--- map, recorded per render.
local function group_at(buf, lnum)
  local id = (group_of[buf] or {})[lnum]
  -- the extension is loaded whenever a header was drawn (its grouper made
  -- it), so it is read from package.loaded, never required on a keypress
  local sa = id and package.loaded['org.extensions.super_agenda']
  if not (sa and sa.folded) then
    return nil
  end
  return sa.folded[id] == true and 'folded' or 'shown'
end

--- org-super-agenda's own key on a group header: fold it, or unfold it.
--- False when the line is not a group header.
local function toggle_group(buf, lnum)
  if not group_at(buf, lnum) then
    return false
  end
  package.loaded['org.extensions.super_agenda'].toggle_group()
  return true
end

--- Unfold the group whose header line is `lnum`, and only that: an unfolded
--- header is left alone. False when the line is not a folded group header.
local function unfold_group(buf, lnum)
  if group_at(buf, lnum) ~= 'folded' then
    return false
  end
  package.loaded['org.extensions.super_agenda'].toggle_group()
  return true
end

--- `l`: unfold what is folded at the entry at point -- the node's subtree in
--- a TODO view (one step, folded -> children -> subtree, never back), else
--- the group whose header the line is, in an agenda view. Unlike `<Tab>`,
--- which cycles, it only reveals: on something already unfolded it does
--- nothing.
local function unfold(buf, lnum)
  local nd = node_at(buf, lnum)
  if nd and #nd.children > 0 then
    local state = states[nd.key] or nd.state or 'folded'
    if state ~= 'subtree' then
      states[nd.key] = state == 'folded' and 'children' or 'subtree'
      refocus(buf, nd.key)
    end
    return
  end
  unfold_group(buf, lnum)
end

local function cycle_all(buf)
  local tree = tree_of(buf)
  if not tree then
    return
  end
  local mode = 'folded'
  for _, nd in ipairs(tree.nodes) do
    local s = states[nd.key] or 'folded'
    if s == 'subtree' then
      mode = 'subtree'
      break
    elseif s == 'children' then
      mode = 'children'
    end
  end
  mode = MODE_NEXT[mode]
  for _, nd in ipairs(tree.nodes) do
    states[nd.key] = mode
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  require('org.agenda.view').refresh()
  pcall(vim.api.nvim_win_set_cursor, 0, { math.min(lnum, vim.api.nvim_buf_line_count(0)), 0 })
end

--- Capture a new entry under the entry at point, in the entry's own file:
--- the Task template of the config, pointed at the entry's outline path.
local function capture_child()
  local item = require('org.agenda.view').item_at_cursor()
  if not (item and item.headline and item.filename) then
    require('org.utils').warn 'org: no entry under the cursor'
    return
  end
  local tpl = vim.deepcopy(require('org.config').opts.capture.templates.t)
  tpl.target = item.filename
  tpl.olp = item.headline:outline_path()
  require('org.capture').capture(tpl)
end

---------------------------------------------------------------------------
-- Statistics cookies
---------------------------------------------------------------------------

local COOKIE_NS = vim.api.nvim_create_namespace 'org.agenda.statistics'

--- Highlight the statistics cookies (`[1/3]`, `[50%]`) of the view's entry
--- lines, the way an org buffer does through treesitter: incomplete in the
--- TODO face, complete in the DONE face
--- (org-checkbox-statistics-todo / -done). A refresh hook, so it runs on
--- every re-render.
local function cookies(buf, b)
  vim.api.nvim_buf_clear_namespace(buf, COOKIE_NS, 0, -1)
  local function mark(row, s, e, done)
    pcall(vim.api.nvim_buf_set_extmark, buf, COOKIE_NS, row, s, {
      end_col = e,
      hl_group = done and 'OrgStatisticDone' or 'OrgStatistic',
      priority = 120,
    })
  end
  for i, line in ipairs(b.lines or {}) do
    local init = 1
    while true do
      local s, e, num, den = line:find('%[(%d*)/(%d*)%]', init)
      if not s then
        break
      end
      mark(i - 1, s - 1, e, num ~= '' and den ~= '' and tonumber(num) == tonumber(den))
      init = e + 1
    end
    init = 1
    while true do
      local s, e, num = line:find('%[(%d*)%%%]', init)
      if not s then
        break
      end
      mark(i - 1, s - 1, e, num ~= '' and tonumber(num) >= 100)
      init = e + 1
    end
  end
end

local function setup_cookies()
  require('org.lazy').on_load('org.agenda.view', 'tree_cookies', function(view)
    view.refresh_hooks.statistics = cookies
  end)
end

--- Record what each group header line of the last render draws (the
--- builder's `super_headers`, line -> group id), so `l` knows which group a
--- header is and whether the extension has it folded. A refresh hook, so it
--- covers the day/week agenda too, which the tree leaves untouched.
local function recall_group_headers(buf, b)
  group_of[buf] = b.super_headers
end

local function setup_groups()
  require('org.lazy').on_load('org.agenda.view', 'tree_group_headers', function(view)
    view.refresh_hooks.group_headers = recall_group_headers
  end)
end

local function setup_keys()
  -- A TODO view folds like an org buffer: <Tab> cycles the node at point
  -- (folded -> children -> subtree -> folded) and does nothing anywhere
  -- else. It must NOT fall back to org.nvim's <Tab> = goto: that opens the
  -- entry's source file (in a split), which is what <Space> / `o` / <CR>
  -- are for. org.nvim sets its own buffer mappings in window.lua *after*
  -- the FileType event (its `shared.setup_mappings` runs inside
  -- agenda.open), so ours must land after the open to win.
  require('org.lazy').on_load('org.agenda', 'tree_keys', function(agenda)
    local open = agenda.open
    agenda.open = function(spec, opts)
      local ok, err = pcall(open, spec, opts)
      if not ok then
        error(err)
      end
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].filetype ~= 'orgagenda' then
        return
      end
      vim.keymap.set('n', '<Tab>', function()
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        local nd = node_at(buf, lnum)
        if nd and #nd.children > 0 then
          cycle_node(buf, nd)
          return
        end
        -- A group header keeps org-super-agenda's own key: it folds the
        -- group. The extension binds it during the first refresh, before
        -- this key, and skips a buffer it already keyed, so without the
        -- fallback its fold would be shadowed here -- and the fallback of
        -- its own handler (org.nvim's `goto`) is what must stay off the
        -- key.
        toggle_group(buf, lnum)
      end, { buffer = buf, desc = 'org: fold the subtree or group at point' })
      vim.keymap.set('n', '<S-Tab>', function()
        cycle_all(buf)
      end, { buffer = buf, desc = 'org: fold every subtree of the view' })
      -- `l` unfolds (never folds): the node's subtree at a folded entry of a
      -- TODO view, the group at a folded header (`… (N)`) anywhere, the
      -- agenda included. It takes the key from log mode, which keeps `vl`.
      vim.keymap.set('n', 'l', function()
        unfold(buf, vim.api.nvim_win_get_cursor(0)[1])
      end, { buffer = buf, desc = 'org: unfold the subtree or group at point' })
      -- `c` is the key the capture is pressed from; <leader>aC is the same
      -- action kept as the longer spelling. The default agenda `c`
      -- (org-agenda-calendar) is unbound in the plugin spec to give it the
      -- key.
      vim.keymap.set('n', 'c', capture_child, {
        buffer = buf,
        desc = 'org: capture a TODO subtree of the entry at point',
      })
      vim.keymap.set('n', '<leader>aC', capture_child, {
        buffer = buf,
        desc = 'org: capture a child of the entry at point',
      })
    end
  end)
end

function M.setup()
  vim.api.nvim_set_hl(0, HINT, { link = 'Comment', default = true })
  setup_render()
  setup_keys()
  setup_cookies()
  setup_groups()
end

return M
