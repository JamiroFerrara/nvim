-- Two-step TODO picker for org.nvim: first the projects, then the open
-- TODOs of the chosen project. A project is one file in ~/org/projects/
-- (the same convention as the capture destination and refile targets in
-- lua/terminal_plugins/org.nvim.lua), shown by its level-1 headline.
-- Registered as the `pick_project_todo` org action and bound to <leader>os
-- there; `:Org pick_project_todo` works too.
local M = {}

local function projects()
  local files = require 'org.files'
  local paths = vim.fn.glob('~/org/projects/*.org', false, true)
  table.sort(paths)
  local out = {}
  for _, path in ipairs(paths) do
    local file = files.get(path)
    local title = vim.fn.fnamemodify(path, ':t:r')
    local open = 0
    if file then
      local first = file.headlines[1]
      if first and first.level == 1 then
        title = first:plain_title()
      end
      for _, hl in ipairs(file.headlines) do
        if hl.todo and not hl:is_done() then
          open = open + 1
        end
      end
    end
    out[#out + 1] = {
      display = { { title }, { '  ' .. open .. ' open', 'Comment' } },
      filename = path,
      lnum = 1,
      value = { path = path, title = title },
    }
  end
  return out
end

--- Pick a project, then an open TODO of its file, and jump to it.
function M.pick()
  local pickers = require 'org.pickers'
  local chosen = pickers.choose { title = 'Project', items = projects() }
  if not chosen then
    return
  end
  local project = chosen[1].value
  local file = require('org.files').get(project.path)
  local items = file and require('org.pickers.sources').todo_items { file } or {}
  if #items == 0 then
    require('org.utils').warn('No open TODO in ' .. vim.fn.fnamemodify(project.path, ':t'))
    return
  end
  local todo = pickers.choose { title = 'TODO: ' .. project.title, items = items }
  if todo then
    pickers.jump(todo[1])
  end
end

return M
