-- The wayfinder ticket kinds in the entry lists (org.nvim): each kind's
-- label reads as an icon, so which kind a ticket is shows at a glance in a
-- list whose entries are otherwise alike. Wired in
-- lua/terminal_plugins/org.nvim.lua: M.setup() wraps org.nvim's tag string,
-- the `:waypoint::wf:wf_grilling:` column an entry line ends with -- one
-- string, one place, so the icon lands on every line of every view that
-- lists entries, the map tree's nested tickets and the flat kind sections
-- alike -- and the `y` view's section headers open with the same glyphs,
-- each kind section standing for the icon its tickets carry.
--
-- A kind is a label of the tracker (skill://wayfinder/org-tracker.md):
-- `wf_map` on the map itself, `wf_<type>` -- research, prototype, grilling,
-- task -- on each ticket. The longer `wayfinder_<type>` spelling of the maps
-- charted before the labels were shortened reads the same, so an old
-- ticket's kind is marked like a new one's. The plain `wf` marker is no
-- kind: it inherits down a map -- that is what puts a capture inside one on
-- it (lua/terminal_plugins/org.nvim.lua, `tags_exclude_from_inheritance`)
-- and is not a ticket until it carries a type.
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

--- The tags string of an entry line with every kind label read as its icon:
--- `:waypoint::wf:wf_grilling:` becomes `:waypoint::wf:💬:`. An entry that is
--- no wayfinder ticket comes back as it was, and so does nil (an entry with
--- no tags at all).
---@param tagstr string|nil the string render.tags_string built
---@return string|nil
function M.show(tagstr)
  if not tagstr or tagstr == '' then
    return tagstr
  end
  return (tagstr:gsub('[^:]+', function(tag)
    local kind = kind_of(tag)
    return kind and M.ICONS[kind] or tag
  end))
end

--- Wrap org.nvim's tag string so every entry list draws the kinds as icons.
function M.setup()
  require('org.lazy').on_load('org.agenda.render', 'wayfinder_tags', function(render)
    local tags_string = render.tags_string
    if not tags_string then
      return
    end
    render.tags_string = function(item)
      return M.show(tags_string(item))
    end
  end)
end

return M
