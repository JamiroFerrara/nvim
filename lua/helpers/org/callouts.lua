-- Callout-style entry lines in the TODO views (wired in
-- lua/terminal_plugins/org.nvim.lua).
--
-- Every listed entry of a TODO view -- the board's sections, the tree
-- (helpers/org/tree.lua), any `todo` / `tags_todo` / `search` list -- is
-- drawn as a callout block, the way the markdown plugin draws a `> [!NOTE]`:
-- a bar in the line's left gutter (`▋`, over the leading spaces -- the agenda
-- prefix's for a listed entry, the tree guides' padding for a nested one) and
-- a full-width background band, both in the entry's state color, so
-- consecutive entries read as stacked blocks. Nothing is added to the source:
-- the state is the entry's TODO keyword, and the color is the one its face
-- already carries -- `ui.todo_keyword_faces` for NEXT / PEND / WARN / TEST
-- (lua/terminal_plugins/org.nvim.lua), the theme's OrgTodo / OrgDone for
-- TODO / DONE -- blended into the background for the band. A listed
-- subheadline without a keyword gets the neutral gray. A day/week agenda
-- view is left alone: its date grid is not a list of entries.
--
-- A refresh hook (like helpers/org/tree.lua's statistics cookies), so it runs
-- on every re-render, and after the tree's own rewrite: the lines it draws on
-- are the final ones.
local M = {}

local NS = vim.api.nvim_create_namespace 'org_agenda_callouts'

-- Left gutter bar, and the band's blend: how much of the state color is
-- mixed into the background (100 = none of it).
local BAR = '▋'
local BLEND = 80

-- The band sits under the plugin's own line highlights -- OrgAgendaClocking,
-- a dimmed blocked entry -- which are drawn at 90.
local BAND_PRIORITY = 50

-- bar/band group of a source face -> the color they were last defined from,
-- so nothing is rewritten while the color stands (a colorscheme change, or a
-- `todo_keyword_faces` edit, moves it).
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

--- Bar and band highlight groups of the face `source`: the bar is drawn in
--- `source`'s color, the band is that color blended into the background.
local function groups_of(source)
  local bar = 'OrgCalloutBar' .. source:gsub('%W', '')
  local band = 'OrgCalloutBand' .. source:gsub('%W', '')
  local color = color_of(source) or color_of('Comment')
  if color and defined[bar] ~= color then
    defined[bar] = color
    vim.api.nvim_set_hl(0, bar, { fg = color })
    vim.api.nvim_set_hl(0, band, { bg = color, blend = BLEND })
  end
  return bar, band
end

--- Draw the callout of every entry line of `b`. The face of a line is its
--- keyword's (org.agenda.render.todo_group, the same the plugin paints the
--- keyword with), the neutral gray when it carries no keyword; the pairs
--- are built once per face per render.
local function draw(buf, b, S)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  if not is_todo_view(S and S.view) then
    return
  end
  local render = require 'org.agenda.render'
  local seen = {}
  for row, item in pairs(b.items or {}) do
    local source = item.todo and render.todo_group(item) or 'Comment'
    local pair = seen[source]
    if not pair then
      pair = { groups_of(source) }
      seen[source] = pair
    end
    local bar, band = pair[1], pair[2]
    local line = row - 1
    vim.api.nvim_buf_set_extmark(buf, NS, line, 0, {
      line_hl_group = band,
      priority = BAND_PRIORITY,
    })
    vim.api.nvim_buf_set_extmark(buf, NS, line, 0, {
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
