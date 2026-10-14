-- Callout-style entry lines in the TODO views (wired in
-- lua/terminal_plugins/org.nvim.lua).
--
-- Every listed entry of a TODO view -- the board's sections, the tree
-- (helpers/org/tree.lua), any `todo` / `tags_todo` / `search` list -- gets a
-- bar in the line's left gutter (`▋`, over the leading spaces -- the agenda
-- prefix's for a listed entry, the tree guides' padding for a nested one) in
-- the entry's state color, the way the markdown plugin marks a `> [!NOTE]`.
-- Nothing is added to the source: the state is the entry's TODO keyword, and
-- the color is the one its face already carries -- `ui.todo_keyword_faces`
-- for NEXT / PEND / WARN / TEST (lua/terminal_plugins/org.nvim.lua), the
-- theme's OrgTodo / OrgDone for TODO / DONE. A listed subheadline without a
-- keyword gets the neutral gray. The bar is drawn in the foreground only:
-- the entry lines keep the buffer's background, no full-width band behind
-- them. A day/week agenda view is left alone: its date grid is not a list of
-- entries.
--
-- A refresh hook (like helpers/org/tree.lua's statistics cookies), so it runs
-- on every re-render, and after the tree's own rewrite: the lines it draws on
-- are the final ones.
local M = {}

local NS = vim.api.nvim_create_namespace 'org_agenda_callouts'

-- Left gutter bar.
local BAR = '▋'

-- bar group -> the color it was last defined from, so nothing is rewritten
-- while it stands.
local defined = {}

--- A TODO-style view lists entries (a `todo`, `tags_todo`, `search`, ...
--- block); an agenda view draws the day grid, where there are no entry lines.
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

--- The color of highlight group `name`: its background if it has one (the
--- keyword faces are chips: base text on the state's color), else its
--- foreground.
local function color_of(name)
  local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
  return hl.bg or hl.fg
end

--- Bar highlight group of an entry's face `source` (`key` names it), drawn in
--- `source`'s color.
local function groups_of(key, source)
  local bar = 'OrgCalloutBar' .. key
  local color = color_of(source) or color_of 'Comment'
  if not color then
    return bar
  end
  if defined[bar] ~= color then
    defined[bar] = color
    vim.api.nvim_set_hl(0, bar, { fg = color })
  end
  return bar
end

--- Draw the bar of every entry line of `b`. The face of a line is its
--- keyword's (org.agenda.render.todo_group, the same the plugin paints the
--- keyword with), the neutral gray when it carries no keyword; the groups
--- are built once per face per render.
local function draw(buf, b, S)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  if not is_todo_view(S and S.view) then
    return
  end
  local render = require 'org.agenda.render'
  local seen = {}
  for row, item in pairs(b.items or {}) do
    local key = item.todo and item.todo:gsub('%W', '') or 'Plain'
    local bar = seen[key]
    if not bar then
      bar = groups_of(key, item.todo and render.todo_group(item) or 'Comment')
      seen[key] = bar
    end
    vim.api.nvim_buf_set_extmark(buf, NS, row - 1, 0, {
      virt_text = { { BAR, bar } },
      virt_text_pos = 'overlay',
    })
  end
end

function M.setup()
  require('org.lazy').on_load('org.agenda.view', 'callouts', function(view)
    view.refresh_hooks.callouts = draw
  end)
end

return M
