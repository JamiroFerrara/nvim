-- The org action finder (wired in lua/terminal_plugins/org.nvim.lua):
-- `<leader>oM` opens a fuzzy picker over what org can do where it is
-- pressed, and runs the entry chosen. org's operations are spread over
-- four places -- the keys this config binds on a headline (`c` capture,
-- `<leader>ai` omp, `<leader>ar` retro), the TODO view's own keys
-- (helpers/org/tree.lua: `r` refile, `<S-Tab>` fold, the digit views), the
-- two view toggles (`§` / `°`, helpers/org/agenda.lua), and org.nvim's own
-- registry (org.actions.list, whose buffers' keys live in
-- `org.config.opts.mappings`) -- so a key one does not remember, or an
-- action that was never given a key at all, is hard to reach. The picker
-- lists them under the scope each one acts on -- the headline at point,
-- the view it is pressed in, org as a whole -- and runs the entry through
-- the very function its own key runs.
--
-- `M.items()` builds the list and is pure: it reads the context (the
-- filetype, the headline or agenda item at point) and returns items whose
-- `value` is the action itself, so callers other than the picker -- tests
-- included -- can use the list without any UI. `M.pick()` is the UI half,
-- and `M.setup()` binds `<leader>oM` buffer-locally: on FileType org, and
-- in the view through the same `org.agenda.open` wrap
-- helpers/org/tree.lua uses, so the key lands after org.nvim's own view
-- mappings.
--
-- Two of the view's actions have no exported function, only their
-- buffer-local mapping -- `r` refile (helpers/org/tree.lua `refile_in_view`)
-- and `<S-Tab>` fold-every-subtree (`cycle_all`). Their items run the
-- mapping's own callback, looked up on the view's buffer: the same entry
-- point the key has, without the module having to widen its surface.
local M = {}

-- The scope suffix of every item, so a list mixing the three reads as
-- "this acts on the headline under the cursor / on the view / on org".
local THIS_HEADLINE = '· this headline'
local THIS_VIEW = '· this view'
local ORG = '· org'

--- The views the view's number keys open: the digit (the item's label),
--- the `agenda.custom_commands` key behind it, and the scope the key opens
--- it with -- the same table helpers/org/agenda.lua binds the digits from
--- (its `CUSTOM_VIEWS`), repeated here because that one is private and the
--- item must open the view with the scope its digit would.
local CUSTOM_VIEWS = {
  { '1', 'o', 'global' },
  { '2', 'g', 'file' },
  { '3', 'w', 'project' },
  { '4', 'p', 'project' },
  { '5', 'y', 'project' },
}

--- One picker item: the label, a `Comment`-highlighted suffix naming the
--- scope (and the key, when the action has one), and the action itself.
---@param label string
---@param suffix string
---@param fn fun()
---@return org.PickerItem
local function item(label, suffix, fn)
  return { display = { { label }, { '  ' .. suffix, 'Comment' } }, value = fn }
end

--- The suffix of an item: its scope, and the key that runs it when it has
--- one.
---@param scope string one of the scope constants above
---@param lhs string|nil
---@return string
local function suffix(scope, lhs)
  return lhs and (scope .. ' · ' .. lhs) or scope
end

--- The first key an org.nvim mapping table binds `name` to (nil when it
--- binds none). `<prefix>` is resolved the way the plugin resolves it.
---@param tables table[] mapping tables (`name = lhs | lhs[] | false`)
---@param name string
---@return string|nil
local function key_of(tables, name)
  local config = require 'org.config'
  for _, t in ipairs(tables) do
    local value = t[name]
    if value then
      local lhs = config.lhs_list(value)[1]
      if lhs then
        return lhs
      end
    end
  end
end

--- `names` ordered the way org.nvim's registry lists them (the section
--- order of org.actions.groups, ties alphabetical so the order is stable).
---@param names string[]
---@return string[]
local function by_group(names)
  local actions = require 'org.actions'
  local rank = {}
  for i, title in ipairs(actions.groups) do
    rank[title] = i
  end
  table.sort(names, function(a, b)
    local ra = rank[actions.list[a].group] or math.huge
    local rb = rank[actions.list[b].group] or math.huge
    if ra ~= rb then
      return ra < rb
    end
    return a < b
  end)
  return names
end

--- The registry names the mapping tables bind, without repeats.
---@param tables table[]
---@param only_global boolean|nil keep only the `global = true` entries
---@return string[]
local function bound_names(tables, only_global)
  local actions = require 'org.actions'
  local seen, out = {}, {}
  for _, t in ipairs(tables) do
    for name, value in pairs(t) do
      local entry = actions.list[name]
      if value and entry and not seen[name] and (not only_global or entry.global) then
        seen[name] = true
        out[#out + 1] = name
      end
    end
  end
  return by_group(out)
end

--- The registry names with `global = true`, i.e. the ones the view -- no
--- org buffer -- can still run.
---@return string[]
local function global_names()
  local actions = require 'org.actions'
  local out = {}
  for name, entry in pairs(actions.list) do
    if entry.global then
      out[#out + 1] = name
    end
  end
  return by_group(out)
end

--- The registry entries as items: org.nvim's own `desc` as the label and
--- the key that runs it, when the mapping tables bind one. The entry runs
--- through the registry's own entry point, `require('org').action`.
---@param names string[]
---@param tables table[] where to look a key up
---@param scope string
---@return org.PickerItem[]
local function registry_items(names, tables, scope)
  local actions = require 'org.actions'
  local out = {}
  for _, name in ipairs(names) do
    local entry = actions.list[name]
    out[#out + 1] = item(entry.desc or name, suffix(scope, key_of(tables, name)), function()
      require('org').action(name)
    end)
  end
  return out
end

--- The four actions that act on the entry at point, `resolve()` looking it
--- up again when one runs (the picker may outlive the cursor position it
--- was opened on). `resolve` returns the headline, its file name and, in
--- the view, the `org.Target` the file-scoped actions take.
---@param resolve fun(): org.Headline|nil, string|nil, org.Target|nil
---@return org.PickerItem[]
local function entry_items(resolve)
  return {
    item('Capture a child entry', THIS_HEADLINE, function()
      local hl, filename = resolve()
      require('helpers.org.capture').under(hl, filename)
    end),
    item('Add a note', THIS_HEADLINE, function()
      local _, _, target = resolve()
      require('helpers.org.notes').add(target)
    end),
    item('OMP: launch on this ticket', THIS_HEADLINE, function()
      require('helpers.org.ai').launch()
    end),
    item('OMP: jump to its session', THIS_HEADLINE, function()
      require('helpers.org.ai').jump()
    end),
  }
end

--- The two views, whichever buffer this is: each opens its kind of view,
--- or hides the one already on screen (helpers.org.agenda.toggle_view, the
--- work behind `§` / `°` in lua/mappings.lua).
---@return org.PickerItem[]
local function global_items()
  local agenda = require 'helpers.org.agenda'
  return {
    item('Agenda', ORG, function()
      agenda.toggle_view('agenda', function()
        require('org').agenda 'a'
      end)
    end),
    item('Project TODO', ORG, function()
      agenda.toggle_view('todo', function()
        require('helpers.org.project').todo_view()
      end)
    end),
  }
end

--- The function a buffer-local mapping on `lhs` runs, so an item for a key
--- whose action is private can go through the mapping itself.
---@param buf integer
---@param lhs string
---@return function|nil
local function buffer_key(buf, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs == lhs and map.callback then
      return map.callback
    end
  end
end

--- The node at point of a TODO view, and the buffer its entry lives in.
---@return integer buf the view's buffer
---@return org.AgendaItem|nil
local function view_entry()
  local buf = vim.api.nvim_get_current_buf()
  local view = require 'org.agenda.view'
  return buf, view.item_at_cursor()
end

--- The items the <leader>oM picker offers on a headline of an org buffer.
---@return org.PickerItem[]
local function org_items()
  local buf = vim.api.nvim_get_current_buf()
  local config = require 'org.config'
  local items = {}
  local file = require('org.files').get_buffer(buf)
  if file and file:headline_on(vim.api.nvim_win_get_cursor(0)[1]) then
    items = entry_items(function()
      local hl = file:headline_on(vim.api.nvim_win_get_cursor(0)[1])
      return hl, file.filename
    end)
  end
  local maps = config.opts.mappings
  vim.list_extend(items, registry_items(bound_names { maps.org or {}, maps.global or {} }, { maps.org or {}, maps.global or {} }, ORG))
  vim.list_extend(items, global_items())
  return items
end

--- The items the <leader>oM picker offers in an orgagenda view: the entry
--- at point, the view's own keys, org.nvim's global actions and the agenda
--- actions the view's mapping table binds.
---@return org.PickerItem[]
local function view_items()
  local buf, entry = view_entry()
  local view = require 'org.agenda.view'
  local maps = require('org.config').opts.mappings
  local items = {}
  if entry then
    vim.list_extend(
      items,
      entry_items(function()
        local it = view.item_at_cursor()
        if not it then
          return nil
        end
        return it.headline, it.filename, view.resolve_target(it)
      end)
    )
  end
  for _, spec in ipairs(CUSTOM_VIEWS) do
    local key, scope = spec[2], spec[3]
    items[#items + 1] = item('View ' .. spec[1], THIS_VIEW, function()
      require('helpers.org.agenda').custom_view(key, scope)
    end)
  end
  local refile = buffer_key(buf, 'r')
  if refile then
    items[#items + 1] = item('Refile the entry at point', THIS_VIEW, refile)
  end
  items[#items + 1] = item('Archive every finished ticket', THIS_VIEW, function()
    require('helpers.org.archive').archive_all_done()
  end)
  items[#items + 1] = item('Retro over the finished tickets', THIS_VIEW, function()
    require('helpers.org.retro').run()
  end)
  local fold = buffer_key(buf, '<S-Tab>')
  if fold then
    items[#items + 1] = item('Fold every subtree', THIS_VIEW, fold)
  end
  vim.list_extend(items, registry_items(global_names(), { maps.global or {}, maps.org or {} }, ORG))
  local agenda = maps.agenda or {}
  local names = {}
  for name, value in pairs(agenda) do
    if value and view.actions[name] then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local label = (name:gsub('_', ' '):gsub('^%l', string.upper))
    items[#items + 1] = item(label, suffix(THIS_VIEW, key_of({ agenda }, name)), function()
      require('org.agenda.view').run_action(name)
    end)
  end
  vim.list_extend(items, global_items())
  return items
end

--- Every action available in the current context, as picker items. Pure:
--- nothing is shown and nothing is run until an item's `value` is called.
---@return org.PickerItem[]
function M.items()
  if vim.bo.filetype == 'orgagenda' then
    return view_items()
  end
  return org_items()
end

--- Pick an action of the current context and run it.
function M.pick()
  require('org.utils').run(function()
    local chosen = require('org.pickers').choose { title = 'Org action', items = M.items() }
    if chosen then
      chosen[1].value()
    end
  end)
end

--- Bind `<leader>oM`, buffer-locally, in org buffers and in the view. The
--- key is not a prefix of anything -- the lowercase `<leader>om` namespace
--- belongs to the roam extension (`<leader>omf`, `<leader>omi`, ...) -- so
--- it can be pressed without the 'timeoutlen' wait an ambiguous prefix
--- would cost, and nothing of org.nvim's is taken off a key.
---@param buf integer
local function map(buf)
  vim.keymap.set('n', '<leader>oM', M.pick, { buffer = buf, desc = 'org: run an action (fuzzy)' })
end

function M.setup()
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'org',
    callback = function(args)
      map(args.buf)
    end,
  })
  -- The view's buffer is filled by org.agenda.open, which sets org.nvim's
  -- own buffer mappings as it goes: binding inside the open, after it,
  -- keeps ours from being shadowed (helpers/org/tree.lua does the same for
  -- the keys it takes from org.nvim).
  require('org.lazy').on_load('org.agenda', 'org_action_finder', function(agenda)
    local open = agenda.open
    agenda.open = function(spec, opts)
      local ok, err = pcall(open, spec, opts)
      if not ok then
        error(err)
      end
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].filetype == 'orgagenda' then
        map(buf)
      end
    end
  end)
end

return M
