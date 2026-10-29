-- Short link descriptions: a `file:` link whose description names a path
-- shows just the name of the file it ends in, so
--   [[file:~/repos/x/module/Agent/src/Listener/AgentListener.php::51][module/Agent/src/Listener/AgentListener.php:51]]
-- reads `AgentListener.php:51`. The directory part is concealed, never
-- rewritten: the whole path stays in the file for a search, a copy or
-- another program (the omp write-back, a script, git), and the line reads
-- the way a person says it.
--
-- Syntax, not an extmark: the highlight is org.nvim's own kind of conceal,
-- so it follows 'conceallevel' and 'concealcursor' as every other piece of
-- org markup does -- revealed on the line the cursor edits, hidden
-- elsewhere. org.nvim keeps the contents of its `orgLink` item to a fixed
-- list, so a link's description cannot be given an item of its own from
-- outside: `file:` links get an item here -- defined after org.nvim's,
-- which is what makes it win -- that contains both the pieces org.nvim
-- already draws (`orgLinkTargetHidden`, `orgLinkBracket`) and the directory
-- part this one hides.
--
-- Only a description that names a path changes: a headline name, a word, an
-- `https:` URL reads as typed, and a block body -- code the markdown plugin
-- draws, where org.nvim conceals no link -- is left alone.
local M = {}

--- A whole `file:` link: `[[file:target]]` or `[[file:target][description]]`.
local LINK = [==[\[\[file:[^]]*\]\%(\[[^]]*\]\)\?\]]==]

--- The leading directories of the description, down to the last `/`: the
--- lookbehind keeps it off the link's target, which can hold slashes too.
local DIR = [=[\(\]\[\)\@<=[^]]*\/]=]

--- Add the items to the org buffer `bufnr`, hiding the description's
--- directories when the buffer draws descriptive links.
---@param bufnr integer
local function add(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= 'org' then
    return
  end
  local ui = require('org.config').opts.ui or {}
  local on = ui.conceal_links ~= false
  local descriptive = vim.b[bufnr].org_link_descriptive
  if descriptive ~= nil then
    on = descriptive and true or false
  end
  vim.api.nvim_buf_call(bufnr, function()
    -- the pieces org.nvim's own `orgLink` carries, plus the description's
    -- directories; `@NoSpell` is the cluster it keeps spelling out of
    vim.cmd('syntax match orgLinkFile /' .. LINK .. '/ contains=orgLinkTargetHidden,orgLinkBracket,orgLinkDescDir,@NoSpell')
    vim.cmd('syntax match orgLinkDescDir /' .. DIR .. '/ contained' .. (on and ' conceal' or ''))
    -- org.nvim carries its links into comments, titles, info values and
    -- table cells through this cluster: an item it does not list there
    -- cannot apply inside them, so the shortened form goes in too.
    vim.cmd 'syntax cluster orgLinks add=orgLinkFile'
  end)
end

function M.setup()
  vim.api.nvim_set_hl(0, 'orgLinkFile', { link = 'OrgLink', default = true })
  -- A syntax item can only be added after org.nvim's (see the header), and
  -- every path that lays the syntax down -- a buffer's first `syntax on`,
  -- `org-toggle-link-display`, a `#+TODO` refresh -- goes through `apply`.
  local syntax = require 'org.syntax'
  local apply = syntax.apply
  syntax.apply = function(bufnr)
    apply(bufnr)
    add((bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr)
  end
  -- A buffer opened before this ran (the one that asked for org.nvim, and
  -- every other org file) has its syntax laid down already: the event ends
  -- in a scheduled pass, which lands after the syntax file has been read.
  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('org_link_file', { clear = true }),
    pattern = 'org',
    callback = function(ev)
      vim.schedule(function()
        add(ev.buf)
      end)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      add(buf)
    end
  end
end

return M
