local M = {}

local function get_project(key)
  local projects = require('helpers.org-menu').projects
  for _, project in ipairs(projects) do
    if project.key == key then
      return project
    end
  end
  return nil
end

---Parse L2 headings from an org file.
---@param filepath string
---@return { text: string, lnum: number }[]
local function parse_l2_headings(filepath)
  local headings = {}
  if vim.fn.filereadable(filepath) == 0 then
    return headings
  end
  local lines = vim.fn.readfile(filepath)
  for i, line in ipairs(lines) do
    local heading = line:match '^%*%*%s+(.+)'
    if heading then
      local title = heading:gsub('%s*:[%w:]*$', ''):gsub('%s+$', '')
      table.insert(headings, { text = title, lnum = i })
    end
  end
  return headings
end

---Find the end line of a heading's section (next heading of same or higher level, or EOF).
---@param lines string[]
---@param start_lnum number
---@param level number
---@return number
local function find_section_end(lines, start_lnum, level)
  local pattern = '^%*' .. string.rep('%*', level - 1) .. '%s'
  for i = start_lnum + 1, #lines do
    if lines[i]:match(pattern) then
      return i - 1
    end
  end
  return #lines
end

---Insert a L3 TODO under a L2 heading and enter Insert mode.
---@param filepath string
---@param target_lnum number|nil @Line number of the L2 heading, or nil to create new
---@param heading_text string @Text of the heading (used if creating new)
local function insert_todo(filepath, target_lnum, heading_text)
  vim.cmd('keepalt edit ' .. vim.fn.fnameescape(filepath))

  if target_lnum then
    -- Navigate to the L2 heading, find end of its section
    vim.api.nvim_win_set_cursor(0, { target_lnum, 1 })
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local end_line = find_section_end(lines, target_lnum, 2)
    vim.api.nvim_win_set_cursor(0, { end_line, 1 })

    -- Go to end of last line and open a new line
    vim.cmd 'keepjumps normal! $'
    local last = vim.fn.getline '.'
    if last ~= '' then
      vim.cmd 'keepjumps normal! o'
    end
  else
    -- Append new L2 heading at EOF, then insert L3 under it
    vim.cmd 'keepjumps normal! G'
    local last = vim.fn.getline '$'
    if last ~= '' then
      vim.cmd 'keepjumps normal! o'
    end
    vim.api.nvim_put({ '** ' .. heading_text, '' }, 'l', true, true)
    vim.api.nvim_win_set_cursor(0, { vim.fn.line '$', 1 })
  end

  -- Insert the L3 TODO
  vim.api.nvim_put({ '*** TODO [#B] ' }, 'l', true, true)
  vim.cmd 'startinsert!'
end

---Open snacks picker to select/create a L2 sub-project, then insert a TODO.
---@param project_key string
function M.capture_with_picker(project_key)
  local project = get_project(project_key)
  if not project then
    vim.notify('org-capture: unknown project key "' .. project_key .. '"', vim.log.levels.ERROR)
    return
  end

  local filepath = vim.fn.expand(project.file)
  local heading = '* ' .. project.name:gsub('^%l', string.upper) .. ' :' .. project.name .. ':'

  -- Create the file if it doesn't exist
  if vim.fn.filereadable(filepath) == 0 then
    vim.fn.writefile({ heading, '' }, filepath)
  end

  local headings = parse_l2_headings(filepath)

  local Snacks = require 'snacks'
  Snacks.picker {
    title = project.name .. ' sub-projects',
    items = headings,
    layout = { preset = 'ivy' },
    format = function(item)
      local label = item.new and ('+ ' .. item.text) or item.text
      return { { label, 'SnacksPickerTitle' } }
    end,
    transform = function(items, ctx)
      local pattern = ctx.filter and ctx.filter.pattern or ''
      if pattern ~= '' then
        local found = false
        for _, item in ipairs(items) do
          if item.text:lower() == pattern:lower() then
            found = true
            break
          end
        end
        if not found then
          table.insert(items, { text = pattern, lnum = nil, new = true })
        end
      end
    end,
    confirm = function(picker, item)
      if not item then
        return
      end
      picker:close()
      insert_todo(filepath, item.lnum, item.text)
    end,
  }
end

---Open the agenda showing all active TODOs across all projects.
function M.open_all_todos()
  local org = require 'orgmode'
  local AgendaTypes = require 'orgmode.agenda.types'
  local Agenda = org.instance().agenda

  local views = {}
  local types = {
    { type = 'tags_todo', match = '/!+NEXT-ARCHIVE', header = 'NEXT' },
    { type = 'tags_todo', match = '/!+TODO-ARCHIVE', header = 'TODO' },
    { type = 'tags_todo', match = '/!+WARN-ARCHIVE', header = 'WARNING' },
    { type = 'tags_todo', match = '/!+PEND-ARCHIVE', header = 'PENDING' },
    { type = 'tags_todo', match = '/!+TEST-ARCHIVE', header = 'TEST' },
  }

  for _, t in ipairs(types) do
    table.insert(
      views,
      AgendaTypes[t.type]:new {
        match_query = t.match,
        todo_ignore_scheduled = false,
        todo_ignore_deadlines = false,
        todo_only = false,
        sorting_strategy = nil,
        agenda_filter = Agenda.filters,
        files = Agenda.files,
        header = t.header,
      }
    )
  end

  Agenda.views = views
  Agenda:prepare_and_render()
end

return M
