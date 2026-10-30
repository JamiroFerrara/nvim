-- Org out to Word: the `:OrgExport` command turns the entry at the cursor --
-- or the whole file, cursor above every headline -- into a .docx built on one
-- of the templates in ~/dotfiles/pandoc.
--
-- The conversion itself is not here. `~/dotfiles/pandoc/org2docx.sh` is the
-- one implementation: it shapes the org text for reading (the top headline as
-- the document title, keywords and tags off the headings, levels renumbered
-- from 1), completes the template with the styles pandoc names and a hand-built
-- template leaves out, and hands the result to pandoc, so Word is filled with
-- the template's header, footer and styles. This module is the editor's half --
-- which lines, which template, which file -- and the `org-docx` skill
-- (skill://org-docx) is the agent's half of the same script, so the two never
-- drift apart.
--
-- Templates are the .docx files beside the script: `novigo_template.docx` is
-- the template `novigo`, and the command's completion reads them from the
-- script itself (`--list`).
local M = {}

local SCRIPT = vim.fn.expand '~/dotfiles/pandoc/org2docx.sh'

--- The org file behind an `org-entry` scratch (helpers/org/agenda.lua): the
--- source buffer's name, which is where an export of the scratch lands beside.
---@param bufnr integer
---@return string
local function source_of(bufnr)
  local src = vim.b[bufnr].org_entry_source
  if not src or not vim.api.nvim_buf_is_valid(src) then
    return vim.api.nvim_buf_get_name(bufnr)
  end
  return vim.api.nvim_buf_get_name(src)
end

--- The lines an export hands over, and the file they belong to.
--- In an `org-entry://` scratch the whole buffer is one entry. In an org file
--- it is the subtree at the cursor; a cursor above every headline exports the
--- whole file.
---@param bufnr integer
---@return string[] lines
---@return string source
local function scope(bufnr)
  local source = source_of(bufnr)
  if vim.b[bufnr].org_entry_source then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), source
  end
  local ok, files = pcall(require, 'org.files')
  local file = ok and files.get_buffer(bufnr) or nil
  local hl = file and file:headline_at(vim.api.nvim_win_get_cursor(0)[1])
  if not hl then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), source
  end
  return vim.api.nvim_buf_get_lines(bufnr, hl.line - 1, hl.end_line, false), source
end

--- The document's name: its first headline without the stars, the keyword, the
--- priority or the tags -- the same text the script turns into the document
--- title -- else the org file's own name.
---@param lines string[]
---@param source string
---@return string
local function document_name(lines, source)
  for _, line in ipairs(lines) do
    local title = line:match '^%*+%s+(.*)$'
    if title then
      title = title:gsub('%s+:[%w_:@%%%-]+:%s*$', '') -- trailing tags
      title = title:gsub('^%[#%w%]%s+', '') -- priority cookie
      title = title:gsub('^[A-Z][A-Z0-9_%-]*%s+', '') -- TODO keyword
      if vim.trim(title) ~= '' then
        return vim.trim(title)
      end
    end
  end
  local base = vim.fn.fnamemodify(source, ':t:r')
  return base ~= '' and base or 'export'
end

--- `document_name` as a file name: lowercase words joined by dashes.
---@param name string
---@return string
local function slug(name)
  local s = name:lower():gsub('[^%w]+', '-'):gsub('^%-+', ''):gsub('%-+$', '')
  if #s > 60 then
    s = vim.trim(s:sub(1, 60):gsub('%-+$', ''))
  end
  return s ~= '' and s or 'export'
end

--- The templates the script offers, by name (`novigo`, ...).
---@return string[]
local function templates()
  local res = vim.system({ SCRIPT, '--list' }, { text = true }):wait()
  if res.code ~= 0 then
    return {}
  end
  return vim.split(res.stdout or '', '\n', { trimempty = true })
end

--- The entry at the cursor through the named template to a .docx beside the
--- org file it came from.
---@param template string|nil template name; the script's default when empty
---@param output string|nil destination; beside the source when empty
---@param open boolean|nil open the document once it is written
function M.export(template, output, open)
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= 'org' then
    vim.notify('org export: not an org buffer', vim.log.levels.WARN)
    return
  end
  if vim.fn.executable 'pandoc' == 0 then
    vim.notify('org export: pandoc is not installed', vim.log.levels.WARN)
    return
  end
  if vim.fn.filereadable(SCRIPT) == 0 then
    vim.notify('org export: missing ' .. SCRIPT, vim.log.levels.WARN)
    return
  end

  local lines, source = scope(bufnr)
  if #lines == 0 then
    vim.notify('org export: nothing to export', vim.log.levels.WARN)
    return
  end

  template = template or ''
  if template ~= '' and not vim.tbl_contains(templates(), template) then
    vim.notify('org export: no template ' .. template .. ' -- known: ' .. table.concat(templates(), ' '), vim.log.levels.WARN)
    return
  end

  if not output or output == '' then
    local dir = source ~= '' and vim.fn.fnamemodify(source, ':h') or vim.fn.getcwd()
    output = dir .. '/' .. slug(document_name(lines, source)) .. '.docx'
  else
    output = vim.fn.fnamemodify(vim.fn.expand(output), ':p')
  end

  local tmp = vim.fn.tempname() .. '.org'
  vim.fn.writefile(lines, tmp)

  local cmd = { SCRIPT, tmp }
  if template ~= '' then
    vim.list_extend(cmd, { '-t', template })
  end
  vim.list_extend(cmd, { '-o', output })

  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      pcall(vim.fn.delete, tmp)
      if res.code ~= 0 then
        local err = vim.trim(res.stderr or '')
        vim.notify('org export: ' .. (err ~= '' and err or 'pandoc failed'), vim.log.levels.WARN)
        return
      end
      vim.notify('org export: ' .. output, vim.log.levels.INFO)
      if open then
        vim.ui.open(output)
      end
    end)
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('OrgExport', function(args)
    M.export(args.fargs[1], args.fargs[2], args.bang)
  end, {
    nargs = '*',
    bang = true,
    complete = function(_, line)
      local words = vim.split(line, '%s+', { trimempty = true })
      -- the arguments already given, not counting the word being typed
      local given = #words - (line:match '%s$' and 0 or 1)
      if given >= 2 then
        return vim.fn.glob((words[#words] or '') .. '*', false, true)
      end
      return templates()
    end,
    desc = 'Export the entry at the cursor (or the whole file) to .docx: :OrgExport [template] [path]',
  })
end

return M
