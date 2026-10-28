-- A darker, full-width band behind org's code snippets (wired in
-- lua/terminal_plugins/org.nvim.lua).
--
-- org.nvim's syntax paints a block body only where there is text, and the
-- language regions (`orgSrcBlock_*`, which win over `orgBlock` on the same
-- line) carry no background at all: a `#+begin_src` snippet reads as ordinary
-- text whose words happen to be colored.
--
-- A `src` block holding markdown is not a snippet: it is an entry's prose --
-- an agent's answer, a note -- written in a block so the markdown plugin
-- renders it. That body is left alone, and the fenced code inside it is banded
-- by the plugin itself (`code.highlight` in lua/plugins/markdown.lua, the same
-- `OrgBlockBg`), so the band lands on the snippet and never on the answer
-- around it.
--
-- Every other row of a verbatim block gets an extmark `line_hl_group`, which
-- fills the row to the window edge -- so the snippet reads as a block, blank
-- and short lines included, and keeps that shape at any width or with any
-- window showing it.
--
-- The colors live in the theme (`OrgBlockBg`, lua/terminal_plugins/
-- theme_catpuccin.lua); nothing here depends on them.
local M = {}

local NS = vim.api.nvim_create_namespace 'org_block_bg'

local GROUP = 'OrgBlockBg'

-- the kinds org.nvim keeps as raw text (lua/org/ui/decorations.lua,
-- VERBATIM_BLOCKS): quote, verse, center and special blocks hold ordinary Org
-- text and get their own face instead.
local VERBATIM = { src = true, example = true, export = true, comment = true }

-- the `src` languages whose body is prose rather than code: the markdown
-- plugin renders the body (queries/org/injections.scm) and bands its fenced
-- code blocks
local PROSE = { markdown = true, md = true }

local pending = {}

-- the block ranges last painted, per buffer: typing inside a block (most of
-- what `TextChangedI` sees) leaves them as they were, and the extmarks -- one
-- per row, the expensive part on a long file -- are not touched for nothing.
local painted = {}

--- The `#+begin_` kind of `line`, lowercased, or nil.
local function begin_kind(line)
  return line:lower():match '^%s*#%+begin_(%S+)'
end

--- The language of a `#+begin_src` line -- the first parameter after the
--- block name -- lowercased, or nil when it carries none.
local function src_language(line)
  return line:lower():match '^%s*#%+begin_src%s+(%S+)'
end

--- Whether `line` closes the block of `kind`. org.nvim ends the region on the
--- same kind and nothing else (`#+end_src` never closes a `#+begin_example`).
local function ends(line, kind)
  local rest = line:lower():match '^%s*#%+end_(.*)$'
  return rest ~= nil and rest:find('^' .. vim.pesc(kind) .. '%f[%A]') ~= nil
end

local function mark(buf, first, last)
  for row = first, last do
    vim.api.nvim_buf_set_extmark(buf, NS, row, 0, { line_hl_group = GROUP })
  end
end

--- Band every code snippet of `buf`, delimiter lines included, so the block is
--- one rectangle rather than a body with two gray lines hanging off it.
local function paint(buf)
  pending[buf] = nil
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    painted[buf] = nil
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local ranges = {}
  local open, first
  for i, line in ipairs(lines) do
    local row = i - 1
    if open then
      if ends(line, open) then
        ranges[#ranges + 1] = { first, row }
        open = nil
      elseif line:match '^%*+%s' then
        -- a headline ends a block (org.nvim's regions stop there too), so a
        -- block left unterminated is banded up to the line before it
        ranges[#ranges + 1] = { first, row - 1 }
        open = nil
      end
    else
      local kind = begin_kind(line)
      local lang = kind == 'src' and src_language(line)
      if kind and VERBATIM[kind] and not (lang and PROSE[lang]) then
        open, first = kind, row
      end
    end
  end
  -- nothing closed it: the band runs to the end of the buffer
  if open then
    ranges[#ranges + 1] = { first, #lines - 1 }
  end
  if vim.deep_equal(ranges, painted[buf]) then
    return
  end
  painted[buf] = ranges
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, range in ipairs(ranges) do
    mark(buf, range[1], range[2])
  end
end

--- Repaint `buf` once per event loop turn: typing fires `TextChangedI` per
--- keystroke and one scan of the buffer is enough for all of them.
local function schedule(buf)
  if pending[buf] then
    return
  end
  pending[buf] = true
  vim.schedule(function()
    paint(buf)
  end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('org_block_bg', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'org',
    desc = 'Band the org verbatim blocks',
    callback = function(args)
      schedule(args.buf)
    end,
  })
  -- opening a new `#+begin_src`, closing one, or deleting a delimiter all
  -- change which rows belong to a block
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = group,
    callback = function(args)
      if vim.bo[args.buf].filetype == 'org' then
        schedule(args.buf)
      end
    end,
  })
  -- `:e!` (and the watcher's reload) drops the extmarks without firing
  -- TextChanged, and a new file under the same number may hold other blocks
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufFilePost' }, {
    group = group,
    callback = function(args)
      painted[args.buf] = nil
      if vim.bo[args.buf].filetype == 'org' then
        schedule(args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args)
      painted[args.buf] = nil
      pending[args.buf] = nil
    end,
  })
end

return M
