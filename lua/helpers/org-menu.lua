---@class OrgAgenda
---@field _build_custom_menu fun(self):OrgMenu
---@field open_custom_menu fun(self)

local config = require('orgmode.config')
local utils = require('orgmode.utils')
local Menu = require('orgmode.ui.menu')
local AgendaTypes = require('orgmode.agenda.types')
local Agenda = require('orgmode').instance().agenda

-- Open the custom menu
function Agenda:open_custom_menu()
  local menu = self:_build_custom_menu()
  menu:open()
end

---@private
function Agenda:_build_custom_menu()
  local menu = Menu:new({
    title = 'My Custom Agenda Menu',
    prompt = 'Press a key for an agenda command',
  })

  -- Basic agenda commands
  menu:add_option({
    label = 'Agenda',
    key = 'a',
    action = function()
      return self:agenda()
    end,
  })

  -- Project TODO submenu
  -- menu:add_option({
  --   label = 'Todo',
  --   key = 't',
  --   action = function()
  --     self:_open_todo_client_submenu()
  --   end,
  -- })


  -- menu:add_option({
  --   label = 'Match',
  --   key = 'm',
  --   action = function()
  --     return self:tags()
  --   end,
  -- })

  -- Quit option
  menu:add_option({
    label = 'Quit',
    key = 'q',
  })

  return menu
end

function Agenda:_open_todo_project_submenu(name)
  local menu = Menu:new({
    title = 'Project TODOs',
    prompt = 'Select a project',
  })

  local custom_commands = self:_build__custom_commands(name)
  if #custom_commands > 0 then
    for _, command in ipairs(custom_commands) do
      menu:add_option({
        label = command.label,
        key = command.key,
        action = command.action,
      })
    end
  end

  -- self:todos({ filter = project.name })

  menu:add_option({
    label = 'Back',
    key = 'b',
    action = function()
      self:open_custom_menu()
    end,
  })
  menu:open()
end

---@private
function Agenda:_open_todo_client_submenu()
  -- Explicit project definitions with custom keys
  local projects = {
    { name = 'dtm',      key = 'd', },
    { name = 'allitude', key = 'a', },
    { name = 'ing',      key = 'i', },
  }

  local menu = Menu:new({
    title = 'Client TODOs',
    prompt = 'Select a client',
  })

  for _, project in ipairs(projects) do
    menu:add_option({
      label = project.name,
      key = project.key,
      action = function()
        self:_open_todo_project_submenu(project.name)
      end,
    })
  end

  menu:add_option({
    label = 'Back',
    key = 'b',
    action = function()
      self:open_custom_menu()
    end,
  })

  menu:open()
end

function Agenda:_build__custom_commands(name)
  local custom_commands = {}
  if not config.org_agenda_custom_commands then
    return {}
  end
  ---@param opts OrgAgendaCustomCommandType
  local get_type_opts = function(opts, id, name)
    local opts_by_type = {
      agenda = {
        span = opts.org_agenda_span,
        start_day = opts.org_agenda_start_day,
        start_on_weekday = opts.org_agenda_start_on_weekday,
      },
      tags = {
        match_query = name .. opts.match,
        todo_ignore_scheduled = opts.org_agenda_todo_ignore_scheduled,
        todo_ignore_deadlines = opts.org_agenda_todo_ignore_deadlines,
      },
      tags_todo = {
        match_query = name .. opts.match,
        todo_ignore_scheduled = opts.org_agenda_todo_ignore_scheduled,
        todo_ignore_deadlines = opts.org_agenda_todo_ignore_deadlines,
      },
    }

    if not opts_by_type[opts.type] then
      return
    end

    opts_by_type[opts.type].sorting_strategy = opts.org_agenda_sorting_strategy
    opts_by_type[opts.type].agenda_filter = self.filters
    opts_by_type[opts.type].files = self.files
    opts_by_type[opts.type].header = opts.org_agenda_overriding_header
    opts_by_type[opts.type].agenda_files = opts.org_agenda_files
    opts_by_type[opts.type].tag_filter = opts.org_agenda_tag_filter_preset
    opts_by_type[opts.type].category_filter = opts.org_agenda_category_filter_preset
    opts_by_type[opts.type].highlighter = self.highlighter
    opts_by_type[opts.type].remove_tags = opts.org_agenda_remove_tags
    opts_by_type[opts.type].id = id

    return opts_by_type[opts.type]
  end
  for shortcut, command in utils.sorted_pairs(config.org_agenda_custom_commands) do
    table.insert(custom_commands, {
      label = command.description or '',
      key = shortcut,
      action = function()
        local views = {}
        for i, agenda_type in ipairs(command.types) do
          local opts = get_type_opts(agenda_type, ('%s_%s_%d'):format(shortcut, agenda_type.type, i), name)
          if not opts then
            utils.echo_error('Invalid custom agenda command type ' .. agenda_type.type)
            break
          end
          table.insert(views, AgendaTypes[agenda_type.type]:new(opts))
        end
        self.views = views
        return self:prepare_and_render():next(function()
          if #self.views > 1 then
            vim.fn.cursor({ 1, 0 })
          end
        end)
      end,
    })
  end
  return custom_commands
end

return Agenda
