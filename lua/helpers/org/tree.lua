-- Subtrees in the TODO views (wired in lua/terminal_plugins/org.nvim.lua).
--
-- A TODO view -- the `o` listed entries (digit 1, and `2`'s whole-file group
-- view), the board (digit 3 / `°`), anything rendering a `todo`, `tags_todo`
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
--   * a done entry is not a subtask, whatever it is nested under: the run it
--     belongs to keeps its line, so a sub-task marked DONE leaves the open
--     entry it hung under and shows in the Done section of the board, if the
--     view has one (a view without a Done block -- `o`, `g`, `p` -- lists no
--     done entries at all, so the finished line simply drops out);
--   * it adds the plain (not TODO) subheadlines of a listed entry as their
--     own lines, rendered like any entry (`org.agenda.render.item_line`), so
--     a subtree shows whole; a subheadline that is itself a listed entry
--     keeps its agenda unit, and its own subtree is not repeated under the
--     ancestor; a done subheadline hangs under an open entry only when the
--     view lists it there (never as a plain child), so it is not pulled back
--     under its ancestor;
--   * the checkbox items of a listed entry's own section (its `- [ ]` list
--     items, up to its first child headline) are added the same way, one
--     line each, one level under the entry: they fold, and count in the
--     `… (N)` size, with the rest of the subtree, and a checked one shows in
--     the DONE face (`OrgCheckboxChecked`). `<CR>` on such a line toggles the
--     box in the entry's own file -- the same toggle a buffer's `<CR>` on a
--     checkbox item runs (helpers/org/mappings.lua), so the entry's (and its
--     ancestors') statistics cookies are recomputed and a last box checked
--     finishes the entry; the file is written
--     (org.nvim's agenda.save_after_edit) and the view re-renders at once.
--     A missing cookie is added first (helpers/org/cookies.lua), so the box
--     counts for the entry's `[0/1]` counter even when the file was never
--     opened in a buffer;
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
--   * an expanded node's subtree is followed by a gap row -- the sibling
--     continuation bar alone (`│`, nothing else) -- when another sibling
--     follows: one row of air between the subtrees, the tree's vertical
--     line running through it. Nothing after the last child of a run, and
--     nothing under a folded node;
--   * `<Tab>` is fold-only in the view: it cycles the node at point
--     (folded -> children -> subtree -> folded), like org's own <Tab>. On a
--     line without a subtree it falls back to the group header's own fold
--     (org-super-agenda's `toggle_group`, which this key would otherwise
--     shadow) -- never to org.nvim's `goto`, which opened the entry's source
--     file in a split (`<S-CR>` / `o` / `<CR>` are what leave the view);
--     `<S-Tab>` cycles every node of the view;
--   * `l` unfolds what is folded at point, one direction only: the node's
--     subtree in a TODO view (one step: folded -> children -> subtree), a
--     folded group header (`… (N)`) in any agenda view. It takes the key
--     from log mode, which keeps its `vl` spelling;
--   * `c` (and its longer spelling `<leader>aC`) captures a new entry as a
--     child of the entry at point -- the work is
--     helpers/org/capture.lua `under`, the same action `c` runs on a
--     headline in an org file (helpers/org/mappings.lua) -- the agenda's
--     default `c` (org-agenda-calendar) is unbound in the plugin spec to
--     give it the key;
--   * `r` on an entry refiles its subtree to another headline of the same
--     view: the picker offers exactly the entry lines on screen, so the
--     target is chosen by eye instead of by outline path, and no line
--     outside the view can be a target. On any other line, and in the
--     day/week agenda, the key keeps org.nvim's `redo` (rebuild the view),
--     as does `gr` anywhere;
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

--- Drop the empty `[0/0]` statistics cookie (and the space before it) from a
--- line the view is about to show: a statistics total of 0 means there is
--- nothing to count, so showing the marker an org file still carries is
--- noise. A view lists files it never loaded, where the on-screen-buffer
--- cookie pass (helpers/org/cookies.lua) could not have cleaned it; this is
--- display only -- neither the file nor a loaded buffer is touched. Only the
--- empty cookie goes: `[0%]` is 0 of N done and every `[n/m]` with m > 0 is a
--- real statistic, so both stay.
--- Returns the cleaned line, and a function mapping an old column of it to
--- its column after the cut, for the line's highlights (nil when nothing was
--- dropped).
local function drop_empty_cookie(text)
  local parts, gaps, init = {}, {}, 1
  while true do
    local s, e = text:find('%s*%[0/0%]', init)
    if not s then
      break
    end
    parts[#parts + 1] = text:sub(init, s - 1)
    gaps[#gaps + 1] = { s, e - s + 1 }
    init = e + 1
  end
  if #gaps == 0 then
    return text, nil
  end
  parts[#parts + 1] = text:sub(init)
  local function shift(col)
    local cut = 0
    for _, g in ipairs(gaps) do
      local stop = g[1] + g[2] - 1
      if col > stop then
        cut = cut + g[2]
      elseif col >= g[1] then -- inside the cut: collapse onto its start
        return g[1] - 1 - cut
      end
    end
    return col - cut
  end
  return table.concat(parts), shift
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
  local nodes, by_unit = {}, {}
  for i, u in ipairs(units) do
    nodes[i] = { unit = u, item = u.item, headline = u.item.headline, box = u.box, children = {}, order = i }
    by_unit[u] = nodes[i]
  end
  for i, nd in ipairs(nodes) do
    local best
    if nd.unit.parent_unit then
      -- a synthetic line (a checkbox item): it carries no headline, so
      -- ancestry has nothing to place it with -- it hangs under the entry
      -- whose text it came from
      best = by_unit[nd.unit.parent_unit]
    else
      for j, other in ipairs(nodes) do
        if i ~= j and is_ancestor(other, nd) then
          if not best or other.headline.line > best.headline.line then
            best = other
          end
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
    local cut
    line, cut = drop_empty_cookie(line)
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
      if cut then
        start, stop = cut(start), cut(stop)
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
  -- A done entry is never a subtask: it is finished, so it stays on the line
  -- its own block put it on -- the board's Done section at the bottom -- and
  -- does not follow its open ancestor into that ancestor's section.
  local hidden = {}
  local function is_subtask(hl)
    if not hl or hl:is_done() then
      return false
    end
    local p = hl.parent
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

  --- The File object behind a headline: the entry's own file while the
  --- headline carries it (a File while it is in the buffer, a path once the
  --- headline was copied or moved).
  local function headline_file(hl)
    local file = hl and hl.file
    if type(file) == 'string' then
      file = require('org.files').get(file)
    end
    return file
  end

  --- The checkbox items of `hl`'s own section, flattened in file order: the
  --- `- [ ]` lines between the headline and its first child. They carry no
  --- headline, so org.nvim never feeds them to an agenda and the view has to
  --- add them itself, one line each, the way it adds the plain subheadlines.
  --- Nested boxes (a checkbox under a checkbox) keep their order but not
  --- their indent: every box is one level under the entry.
  local function checkbox_children(hl, file)
    local lines = file and file.lines
    if not lines or not hl.body_end or hl.body_end <= hl.line then
      return nil
    end
    local _, all = require('org.lists').parse_region(lines, hl.line + 1, hl.body_end)
    local out
    for _, it in ipairs(all) do
      if it.checkbox then
        out = out or {}
        out[#out + 1] = { lnum = it.lnum, raw = lines[it.lnum], checkbox = it.checkbox }
      end
    end
    return out
  end

  --- Headlines of `item`'s own subtree the view does not list: the plain
  --- (not TODO) subheadlines org.nvim never feeds an agenda. A listed entry
  --- still shows its whole subtree, as an org file does; a listed
  --- subheadline's own subtree is left to its own unit, not repeated here.
  local function plain_children(item)
    local hl = item.headline
    local file = headline_file(hl)
    local all = file and file.headlines
    if not all or not hl.end_line or hl.end_line <= hl.line then
      return nil
    end
    local set = listed[item.filename]
    -- a done entry belongs to the Done section, not under an open ancestor:
    -- unless the ancestor is itself done, a finished subheadline is left to
    -- its own block (its subtree is skipped with it, never re-added here)
    local open_entry = not hl:is_done()
    local out, stop
    for _, h in ipairs(all) do
      if h.line > hl.end_line then
        break
      elseif h.line <= hl.line then -- an ancestor, or the entry itself
      elseif stop and h.line <= stop then -- inside a listed entry's subtree
      elseif set and set[h.line] then
        stop = h.end_line
      elseif open_entry and h:is_done() then
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

  --- A unit for one checkbox line of an entry: the line is its own node, one
  --- level under the entry (which its `parent_unit` names, an item carrying
  --- no headline cannot be placed by ancestry). Its item is a stand-in for
  --- the key the cursor is returned to after a re-render; it is kept out of
  --- the view's line items, so the entry keys act on nothing here. `box` is
  --- what `<CR>` toggles: the line it came from, in the entry's own file.
  local function box_unit(bx, owner, item)
    local text = vim.trim(bx.raw)
    local s, e = text:find '%[[ xX%-]%]'
    local group = bx.checkbox == 'X' and 'OrgCheckboxChecked' or bx.checkbox == '-' and 'OrgCheckboxPartial' or 'OrgCheckbox'
    -- the box state is left out of the key: toggling the box rewrites the
    -- text, and the cursor comes back to the line it toggled
    local title = text:gsub('%[[ xX%-]%]%s*', '', 1)
    local file = item.filename or item.bufnr
    return {
      item = { title = title, filename = item.filename, bufnr = item.bufnr, lnum = bx.lnum },
      parent_unit = owner,
      box = {
        file = file,
        lnum = bx.lnum,
        raw = bx.raw,
        text = text,
        -- a synthetic line's hls are `{ start, end, group }` (0-based, end
        -- exclusive), the shape reorder shifts for the guide
        hls = s and { { s - 1, e, group } } or {},
        key = tostring(file) .. ':' .. title,
      },
      rows = {},
    }
  end

  -- units: an item line with the entry-text lines that follow it, plus a
  -- line per checkbox item of the entry's own section and one per plain
  -- subheadline of it; every other line is a break between runs. The boxes
  -- come first: they sit in the entry's text, above every child headline of
  -- the file.
  local units = {}
  --- The checkbox lines of headline `hl`, one node each, nested under the
  --- unit `owner` (the entry line they follow).
  local function add_boxes(hl, owner, item)
    if not hl then
      return
    end
    for _, bx in ipairs(checkbox_children(hl, headline_file(hl)) or {}) do
      units[#units + 1] = box_unit(bx, owner, item)
    end
  end

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
      add_boxes(items[l].headline, u, items[l])
      -- the plain subheadlines: a hidden subtask is re-added here, and its
      -- own boxes come with it, so a subtree nested under a listed entry
      -- shows its checkboxes the same way the listed entry does
      for _, h in ipairs(plain_children(items[l]) or {}) do
        local cu = plain_unit(h, u.ctx)
        if cu then
          units[#units + 1] = cu
          add_boxes(h, cu, cu.item)
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

    --- The gap row that follows an expanded node's children: the sibling
    --- continuation bar alone (`│`, `│  │`), with nothing else on it. It
    --- carries no item, so the view's cursor keys skip it like a body line.
    local function gap(base, bars)
      return { text = pad(base) .. (bars:gsub('%s+$', '')), hls = {} }
    end

    --- `base` is the root's content column (its agenda prefix width); a
    --- child's text starts there, one `guide` (and `bars`) deeper, with no
    --- agenda prefix of its own. `last_sibling` is whether `nd` closes its
    --- parent's child list, which decides whether a gap row is drawn under
    --- its subtree.
    local function walk(nd, base, guide, bars, last_sibling)
      if not visible(nd) then
        return
      end
      if nd.box and not nd.parent then
        -- a box hangs under its entry, always: without it there is nothing
        -- to nest the line under, so it is left out
        return
      end
      local total = #nd.children > 0 and count_desc(nd) or 0
      local off = total > 0 and hidden_desc(nd) or 0
      local suffix = total > 0 and ((off > 0 and ' … (' or ' (') .. total .. ')') or ''
      if nd.parent then
        local text, hls
        if nd.box then
          -- the checkbox line, as the entry's file writes it (its marker
          -- highlighted): it carries no agenda prefix to drop
          text, hls = nd.box.text, nd.box.hls
        else
          text, hls = no_prefix(nd)
        end
        local lead = pad(base) .. guide
        local shifted = {}
        for _, h in ipairs(hls) do
          shifted[#shifted + 1] = { h[1] + #lead, h[2] + #lead, h[3], h[4] }
        end
        -- a box line carries no item: the view's entry keys must skip it the
        -- way they skip a body line
        order[#order + 1] = {
          text = lead .. text,
          hls = shifted,
          item = not nd.box and nd.item or nil,
          suffix = suffix,
        }
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
      local shown = false
      for i, ch in ipairs(nd.children) do
        local last = i == #nd.children
        if visible(ch) then
          shown = true
        end
        walk(ch, base, bars .. (last and '└─ ' or '├─ '), bars .. (last and '   ' or '│  '), last)
      end
      -- One row of air between a node's subtree and the sibling below it,
      -- so the bar runs on through the gap. Only when something is shown
      -- (a folded node's children stay hidden) and only between siblings:
      -- after the last child, or a root, there is nothing to link to.
      if shown and not last_sibling then
        order[#order + 1] = gap(base, bars)
      end
    end
    for _, nd in ipairs(run_roots) do
      local c = nd.unit.ctx or ctx
      local kind = c.kind or (c.agenda and 'agenda' or 'todo')
      local prefix = render.prefix(nd.item, kind)
      walk(nd, vim.fn.strdisplaywidth(prefix), '', '', true)
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
    -- A line the plugin rebuilds on its own -- agenda/view/edit.lua
    -- (org-agenda-change-all-lines) rewrites a line after a clock-in or a
    -- change made outside the view -- comes straight from item_line, past
    -- the view builder: keep the empty `[0/0]` cookie out of it too.
    local item_line = render.item_line
    render.item_line = function(it, ctx)
      local text, hls, line_hl = item_line(it, ctx)
      if text then
        local clean, shift = drop_empty_cookie(text)
        if shift then
          for _, h in ipairs(hls or {}) do
            h[1], h[2] = shift(h[1]), shift(h[2])
          end
          text = clean
        end
      end
      return text, hls, line_hl
    end
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

--- Put the cursor back on the entry with `key` after a re-render: the entry
--- line the view lists it on, or the checkbox line it is the key of.
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
    for lnum, nd in pairs(tree.by_line) do
      if nd.box and nd.box.key == key then
        pcall(vim.api.nvim_win_set_cursor, 0, { lnum, 0 })
        return
      end
    end
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

--- `<CR>` on a checkbox line of a TODO view: toggle that box in the entry's
--- own file, the same toggle a buffer's `<CR>` on a checkbox item runs
--- (helpers/org/mappings.lua, through org.lists), so the entry's own and its
--- ancestors' statistics cookies are recomputed and checking the last box
--- finishes the entry. The entry's file is loaded when no buffer holds it, a
--- missing `[n/m]` cookie is added first -- nothing did it for a file the
--- view listed without ever opening it in a buffer, and the box must count
--- for it -- and the file is written (org.nvim's agenda.save_after_edit),
--- the way an edit made from the view is.
---@param buf integer the view's buffer
---@param box table the node's `box` (file, line, text)
local function toggle_box(buf, box)
  local utils = require 'org.utils'
  local bufnr = type(box.file) == 'number' and box.file or utils.find_buffer(box.file)
  if not bufnr then
    local ok, loaded = pcall(utils.load_buffer, box.file)
    bufnr = ok and loaded or nil
  end
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    utils.warn 'org: cannot find the file of the checkbox'
    return
  end
  -- the entry may have moved since the render (an edit elsewhere in the
  -- file): the line carrying the same text is the one to toggle
  local lnum = require('org.agenda.view').locate_line(bufnr, { lnum = box.lnum, raw = box.raw })
  local item = lnum and require('org.lists').item_at(bufnr, lnum)
  if not (item and item.checkbox) then
    utils.warn 'org: the checkbox has moved; press gr to rebuild the view'
    return
  end
  local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.api.nvim_win_set_cursor(0, { item.lnum, 0 })
    require('org.lists').toggle_checkbox()
  end)
  if not ok then
    utils.warn('org: ' .. tostring(err))
    return
  end
  require('helpers.org.cookies').ensure(bufnr)
  if require('org.config').opts.agenda.save_after_edit then
    utils.save_buffer_or_warn(bufnr)
  end
  refocus(buf, box.key)
end

--- Capture a new entry under the entry at point, in the entry's own file.
--- The work is `helpers.org.capture.under`, shared with the `c` mapping of
--- an org file (helpers/org/mappings.lua); here the entry is the agenda
--- item at the cursor, which carries its file.
local function capture_child()
  local item = require('org.agenda.view').item_at_cursor()
  if not (item and item.headline and item.filename) then
    require('org.utils').warn 'org: no entry under the cursor'
    return
  end
  require('helpers.org.capture').under(item.headline, item.filename)
end

---------------------------------------------------------------------------
-- Refile to a headline of the view
---------------------------------------------------------------------------

--- The file an entry's headline lives in, as a key for comparing two
--- entries: the path when the headline still knows its file, else the
--- buffer number. A headline's `file` is the File object while it is in the
--- buffer, and a path string (or nothing) once it was copied or moved.
local function entry_file(hl, item)
  local f = hl and hl.file
  if type(f) == 'table' then
    return f.filename or (f.bufnr and tostring(f.bufnr))
  elseif type(f) == 'string' then
    return f
  end
  return item.filename or (item.bufnr and tostring(item.bufnr))
end

--- The entry lines the view at `buf` shows: one per line of its
--- `line_items` -- the table the tree reorder keeps to the lines actually
--- on screen, synthetic subheadline lines included -- in buffer order, one
--- per headline (two blocks can list the same entry).
---@param buf integer
---@return { item: table, hl: org.Headline }[]
local function view_entries(buf)
  local state = require('org.agenda.view').state_of(buf)
  local items = (state and state.line_items) or {}
  local lines = vim.tbl_keys(items)
  table.sort(lines)
  local out, seen = {}, {}
  for _, l in ipairs(lines) do
    local item = items[l]
    local hl = item.headline
    if hl then
      local key = entry_file(hl, item) .. ':' .. tostring(hl.line)
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = { item = item, hl = hl }
      end
    end
  end
  return out
end

--- A one-line label for a destination: keyword, title and tags as the view
--- draws the entry, plus the file name when the view spans several files.
local function entry_label(entry, multi)
  local item, hl = entry.item, entry.hl
  local label = (hl.todo and hl.todo .. ' ' or '') .. (item.title or hl:plain_title())
  if item.tags and #item.tags > 0 then
    label = label .. ' :' .. table.concat(item.tags, ':') .. ':'
  end
  if multi and item.filename then
    label = label .. '  (' .. vim.fn.fnamemodify(item.filename, ':t') .. ')'
  end
  return label
end

--- Refile the entry at point to another headline the same view shows: the
--- destinations are the entry lines on screen, minus the source's own
--- subtree (a move inside it is org.nvim's "Cannot refile to position
--- inside the tree" error). `org.refile` moves the subtree, saving a
--- destination that is not on screen, and the view is re-rendered right
--- after, so the entry is seen leaving its section; with
--- `agenda.save_after_edit` the source file is written, the way an edit
--- from the view is.
---
--- Returns true when the key was taken -- a TODO view with an entry at
--- point, picker or not -- so the caller can leave `r` to org.nvim's redo
--- everywhere else.
---@param buf integer
---@return boolean
local function refile_in_view(buf)
  local view = require 'org.agenda.view'
  local utils = require 'org.utils'
  local state = view.state_of(buf)
  if not (state and is_todo_view(state.view)) then
    return false
  end
  local item = view.item_at_cursor()
  if not (item and item.headline) then
    return false
  end
  local src = view.resolve_target(item)
  if not src then
    return true
  end
  local hl = item.headline
  local file = entry_file(hl, item)
  local heads, seen_files, files = {}, {}, 0
  for _, e in ipairs(view_entries(buf)) do
    local h = e.hl
    local name = entry_file(h, e.item)
    local inside = name == file and h.line >= hl.line and h.line <= (hl.end_line or hl.line)
    if not inside then
      heads[#heads + 1] = e
      if name and not seen_files[name] then
        seen_files[name] = true
        files = files + 1
      end
    end
  end
  if #heads == 0 then
    utils.warn 'org: no other entry in the view to refile into'
    return true
  end
  for _, e in ipairs(heads) do
    e.label = entry_label(e, files > 1)
  end
  utils.run(function()
    local choice = utils.select(heads, {
      prompt = 'Refile "' .. (item.title or '') .. '" to',
      kind = 'org_refile',
      format_item = function(e)
        return e.label
      end,
    })
    if not choice then
      return
    end
    local dest = view.resolve_target(choice.item)
    if not dest then
      return
    end
    dest.label = choice.label
    require('org.refile').refile(src, { dest = dest })
    if require('org.config').opts.agenda.save_after_edit then
      require('org.utils').save_buffer_or_warn(src.bufnr)
    end
    view.refresh()
  end)
  return true
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
  -- entry's source file (in a split), which is what <S-CR> / `o` / <CR>
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
      -- <CR> stays the entry scratch (helpers/org/agenda.lua binds it as the
      -- `entry_scratch` action) on every line of the view but a checkbox
      -- line, which it toggles instead, the way <CR> on a checkbox item
      -- toggles it in an org buffer.
      vim.keymap.set('n', '<CR>', function()
        local nd = node_at(buf, vim.api.nvim_win_get_cursor(0)[1])
        if nd and nd.box then
          toggle_box(buf, nd.box)
          return
        end
        require('org.agenda.view').actions.entry_scratch()
      end, { buffer = buf, desc = 'org: toggle the checkbox at point / open the entry scratch' })
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
      -- `r` on an entry of a TODO view refiles its subtree into another
      -- headline of the same view (refile_in_view); anywhere else -- a
      -- section rule, a group header, a folded count line, a date-agenda
      -- buffer -- it stays org.nvim's `redo`, the rebuild of the view.
      -- `gr` (redo_all) rebuilds from anywhere.
      vim.keymap.set('n', 'r', function()
        if not refile_in_view(buf) then
          require('org.agenda.view').run_action 'redo'
        end
      end, { buffer = buf, desc = 'org: refile the entry to a headline of the view / redo' })
    end
  end)
end

--- The file name a node's entry lives in (a path, else the buffer number).
---@param nd table
---@return string
local function name_of(nd)
  local f = nd.headline and nd.headline.file
  return (f and f.filename) or nd.item.filename or tostring(nd.item.bufnr)
end

--- Open the subtree of the node on line `lnum` of `buf`, one step like `l`
--- (folded -> children -> subtree), when that node is the entry `hl` -- same
--- file and line. A state change refused for the entry's unfinished children
--- calls this (helpers/org/reveal.lua), so the child that blocks it comes on
--- screen the way <Tab> would show it. True when a subtree was opened.
---@param buf integer
---@param lnum integer
---@param hl org.Headline|nil the entry the change was about (nil: any node)
---@return boolean
function M.reveal(buf, lnum, hl)
  local nd = node_at(buf, lnum)
  if not (nd and #nd.children > 0) then
    return false
  end
  if hl then
    local head = nd.headline
    local name = hl.file and hl.file.filename
    if not (head and head.line == hl.line and (not name or name_of(nd) == name)) then
      return false
    end
  end
  local state = states[nd.key] or nd.state or 'folded'
  if state == 'subtree' then
    return false
  end
  states[nd.key] = state == 'folded' and 'children' or 'subtree'
  refocus(buf, nd.key)
  return true
end

function M.setup()
  vim.api.nvim_set_hl(0, HINT, { link = 'Comment', default = true })
  setup_render()
  setup_keys()
  setup_cookies()
  setup_groups()
end

return M
