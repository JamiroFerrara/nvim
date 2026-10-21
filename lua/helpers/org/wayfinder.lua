-- The wayfinder ticket kinds in the entry lists (org.nvim): each kind's
-- label reads as an icon on the ticket's line, so which kind a ticket is
-- shows at a glance in a list whose entries are otherwise alike.
--
-- The icon sits immediately before the entry's state keyword -- right where
-- the line's own text starts -- for a root line and a nested one alike. It
-- is inserted into the parts org.nvim builds the line from
-- (`render.item_parts`), after the agenda prefix: the tree helper cuts a
-- nested line's prefix (helpers/org/tree.lua, `no_prefix`) and keeps what
-- follows, so a ticket nested under its blocker draws its guide first and
-- its kind next -- `└─ 🛠 TODO ...` -- while a listed line reads
-- `  waypoint:    today 11:20  🛠 DONE ...`. The part's own face is left to
-- the theme, so the glyph draws in the line's colors, and the space before
-- it comes from the prefix (or from the tree guide, on a nested line), which
-- is why the `tags` `prefix_format` below ends in one.
--
-- The icon is a column, not a per-line spur: a block that shows any kind
-- reserves its three columns on every line it lists, so the keywords of a
-- section stay in one column where a wayfinder ticket sits among plain
-- entries -- `🛠 DONE Discard the ai-backend conversion` above
-- `   DONE IPP fix con Davide` -- and a block that shows no wayfinder
-- ticket is drawn exactly as it was.
--
-- A kind is a label of the tracker (skill://wayfinder/org-tracker.md):
-- `wf_map` on the map itself, `wf_<type>` -- research, prototype, grilling,
-- task -- on each ticket. The longer `wayfinder_<type>` spelling of the maps
-- charted before the labels were shortened reads the same, so an old
-- ticket's kind is marked like a new one's. The plain `wf` marker is no
-- kind: it inherits down a map -- that is what puts a capture inside one on
-- it (lua/terminal_plugins/org.nvim.lua, `tags_exclude_from_inheritance`)
-- and is not a ticket until it carries a type.
--
-- The `y` view's kind sections are headed by the same glyphs
-- (lua/terminal_plugins/org.nvim.lua, `wf_type_section`): the section names
-- the kind in words, its tickets carry the icon.
local M = {}

--- The kinds and the icon each marks its line with. A label naming no kind
--- here -- `wf` itself -- is left as it is written.
M.ICONS = {
  map = '🗺',
  research = '🔬',
  prototype = '🧪',
  grilling = '💬',
  task = '🛠',
}

--- The kind a tag names, or nil for any other tag: the two spellings of one
--- label, `wf_<type>` and `wayfinder_<type>`.
---@param tag string
---@return string|nil
local function kind_of(tag)
  local kind = tag:match '^wf_(%a+)$' or tag:match '^wayfinder_(%a+)$'
  return kind and M.ICONS[kind] and kind or nil
end

--- The kind `hl` names, or nil for a headline that is no wayfinder ticket.
--- Only the entry's own tags are read -- the labels are excluded from tag
--- inheritance -- so a ticket's children are not of its kind.
---@param hl org.Headline|nil
---@return string|nil
function M.kind(hl)
  for _, tag in ipairs((hl and hl.tags) or {}) do
    local kind = kind_of(tag)
    if kind then
      return kind
    end
  end
  return nil
end

--- The icon of `hl`'s kind, or '' for a headline that is no wayfinder ticket
--- (and for no headline at all).
---@param hl org.Headline|nil
---@return string
function M.icon(hl)
  local kind = M.kind(hl)
  return kind and M.ICONS[kind] or ''
end

--- The part org.nvim drew the entry's state keyword on, or nil when the
--- entry carries none (a plain subheadline a view lists). The keyword is
--- pushed through org-agenda-todo-keyword-format, so the part is that
--- format's product -- empty for a keyword the format drops, which is a line
--- with nothing to put an icon before.
---@param parts table[] the parts `render.item_parts` built
---@param item org.AgendaItem
---@return integer|nil
local function keyword_part(parts, item)
  local kw = item.todo
  if not kw or kw == '' then
    return nil
  end
  local fmt = require('org.config').opts.agenda.todo_keyword_format or '%-1s'
  if fmt == '' then
    return nil
  end
  local ok, drawn = pcall(string.format, fmt, kw)
  drawn = ok and drawn or kw
  for i, part in ipairs(parts) do
    if part[1] == drawn then
      return i
    end
  end
  return nil
end

--- Wrap org.nvim's line builder so every entry list draws the wayfinder
--- kinds as icons, each immediately before the state keyword.
function M.setup()
  require('org.lazy').on_load('org.agenda.render', 'wayfinder_icons', function(render)
    local utils = require 'org.utils'

    --- The field an entry's kind is drawn in: the glyph with the gap that
    --- follows it, three display columns wide. A line that carries no kind
    --- gets the same field in blanks, which is what keeps the keywords of a
    --- block in one column when one entry of it is a ticket and the next is
    --- not.
    local function field(icon)
      return icon .. string.rep(' ', math.max(3 - utils.width(icon), 1))
    end

    -- The field is the block's, not the line's: a block that shows any kind
    -- reserves it on every line it lists, and one that shows none keeps the
    -- layout it always had. The decision is taken on the list the block
    -- settled on (`apply_limits`, before any of its lines is built) and kept
    -- on the ctx org.nvim copies into every line of that block.
    local apply_limits = render.apply_limits
    if apply_limits then
      render.apply_limits = function(list, kind, ctx)
        local out = apply_limits(list, kind, ctx)
        if ctx then
          ctx.wayfinder_field = false
          for _, item in ipairs(out) do
            if M.kind(item.headline) then
              ctx.wayfinder_field = true
              break
            end
          end
        end
        return out
      end
    end

    local item_parts = render.item_parts
    if not item_parts then
      return
    end
    render.item_parts = function(item, ctx)
      local parts = item_parts(item, ctx)
      -- no headline at all (the time-grid rows) and no label both answer ''
      local icon = M.icon(item.headline)
      if icon == '' and not (ctx and ctx.wayfinder_field) then
        return parts
      end
      local at = keyword_part(parts, item)
      if not at then
        return parts
      end
      table.insert(parts, at, { field(icon), nil })
      -- the priority face runs to the keyword, measured off the parts before
      -- it (org.agenda.render.item_line): the field is one of them now
      if parts.priority_index and parts.priority_index >= at then
        parts.priority_index = parts.priority_index + 1
      end
      return parts
    end
  end)
end

return M
