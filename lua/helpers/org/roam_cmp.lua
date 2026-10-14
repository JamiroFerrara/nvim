-- nvim-cmp source for org-roam links (registered in lua/plugins/cmp.lua).
--
-- Typing `[[` in a roam file lists the index's nodes -- titles and aliases --
-- and, when what you typed is not an existing node, offers to create one, the
-- way obsidian.nvim completes `[[` in the markdown vault. Accepting an
-- existing node replaces `[[<typed>` with an `id:` link to it; accepting the
-- create item runs the roam capture (org-roam-node-insert) and links the new
-- node. The <prefix>omi picker stays for Visual mode and for the terminal
-- session, where nvim-cmp is not loaded.
--
-- The source is available only for org buffers inside the roam directory
-- (extensions.roam.directory), so the plugin's own `[[` completions (link
-- types, `#+` keywords) keep the floor everywhere else.

local Source = {}
Source.__index = Source

local ns = vim.api.nvim_create_namespace 'org.roam.cmp'

--- The roam db when `bufnr` is a roam file, else nil.
---@param bufnr integer
---@return table|nil
local function db_for(bufnr)
  if vim.bo[bufnr].filetype ~= 'org' then
    return nil
  end
  local ok, ext = pcall(require, 'org.extensions')
  if not ok or not ext.opts 'roam' then
    return nil
  end
  local ok_db, db = pcall(require, 'org.extensions.roam.db')
  if not ok_db or not db.is_roam_file(vim.api.nvim_buf_get_name(bufnr)) then
    return nil
  end
  return db
end

function Source.new()
  return setmetatable({}, Source)
end

function Source:is_available()
  return db_for(vim.api.nvim_get_current_buf()) ~= nil
end

function Source:get_trigger_characters()
  return { '[' }
end

-- the `[[<search>` text ending at the cursor, the shape obsidian.nvim uses
function Source:get_keyword_pattern()
  return [=[\%(^\|[^\[]\)\zs\[\{1,2}[^\]]\+\]\{,2}]=]
end

function Source:complete(params, callback)
  local ctx = params.context
  local before = ctx.cursor_before_line
  local open, search = before:match '()%[%[([^%]]*)$'
  local db = open and db_for(ctx.bufnr)
  -- not a node link: a typed link type (`id:`, `file:`, `https:`), a headline
  -- anchor (`#`), a ref (`*`) or a file path (`/`)
  if not db or not search or search:match '^%a[%w+%-]*:' or search:match '^[#*/]' then
    return callback { items = {}, isIncomplete = false }
  end
  local node = require 'org.extensions.roam.node'
  local format = require('org.links').format
  local row = ctx.cursor.row - 1
  -- replace the whole `[[<search>` and, cursor inside one, the closing `]]`
  local range = {
    start = { line = row, character = open - 1 },
    ['end'] = { line = row, character = #before + (ctx.cursor_after_line:sub(1, 2) == ']]' and 2 or 0) },
  }
  local items, seen = {}, {}
  for _, c in ipairs(node.candidates()) do
    if not seen[c.name] then
      seen[c.name] = true
      local link = format('id:' .. c.node.id, c.name)
      items[#items + 1] = {
        label = '[[' .. c.name .. ']]',
        kind = 18, -- Reference
        detail = node.display(c.node, c.name),
        documentation = { kind = 'markdown', value = '`' .. link .. '`\n\n' .. c.node.file },
        textEdit = { newText = link, range = range },
      }
    end
  end
  local title = vim.trim(search)
  if title ~= '' and not db.by_title(title) then
    items[#items + 1] = {
      label = '[[' .. title .. ']] (create)',
      kind = 18, -- Reference
      detail = 'Create node',
      documentation = { kind = 'markdown', value = 'Create `' .. title .. '` and link to it' },
      textEdit = { newText = '', range = range },
      data = { title = title },
    }
  end
  callback { items = items, isIncomplete = true }
end

-- the create item: capture the node, then link it where the item was accepted
-- (the text `[[<typed>` is already gone by the time this runs)
function Source:execute(item, callback)
  local data = item.data
  if not (data and data.title) or not db_for(vim.api.nvim_get_current_buf()) then
    return callback()
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local mark = vim.api.nvim_buf_set_extmark(bufnr, ns, pos[1] - 1, pos[2], {})
  local id = require('org.extensions.roam.capture').capture {
    node = { title = data.title },
    finalize = 'insert_link',
    call_location = { bufnr = bufnr, mark = mark, ns = ns },
    link_description = data.title,
  }
  if not id then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, mark)
  end
  callback()
end

return Source
