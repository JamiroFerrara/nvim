-- A darker, full-width band behind org's code snippets, capped by a rule
-- (wired in lua/terminal_plugins/org.nvim.lua).
--
-- org.nvim's syntax paints a block body only where there is text, and the
-- language regions (`orgSrcBlock_*`, which win over `orgBlock` on the same
-- line) carry no background at all: a `#+begin_src` snippet reads as ordinary
-- text whose words happen to be colored.
--
-- Every row of a snippet gets an extmark `line_hl_group`, which fills the row
-- to the window edge -- so the snippet reads as a block, blank and short lines
-- included, and keeps that shape at any width or with any window showing it.
-- Its opening and closing lines carry a rule (`──── lua ─────…`) instead of
-- `#+begin_src lua` / `#+end_src`: the block is framed, the delimiter noise is
-- gone, and the language stays readable at the left.
--
-- A `src` block holding markdown is not a snippet: it is an entry's prose --
-- an agent's answer, a note -- written in a block so the markdown plugin
-- renders it. That body is left alone, and the fenced code inside it is banded
-- by the plugin itself (`code.highlight` in lua/plugins/markdown.lua, the same
-- `OrgBlockBg`) and ruled here, so band and rules land on the snippet and
-- never on the answer around it.
--
-- The colors live in the theme (`OrgBlockBg`, lua/terminal_plugins/
-- theme_catpuccin.lua); nothing here depends on them.
local M = {}

local NS = vim.api.nvim_create_namespace 'org_block_bg'

local BAND = 'OrgBlockBg'

-- the rule's dashes, and the groups that paint them: the dashes in the vault's
-- rule color, the label in the page's text color, both on the band's
-- background (a virtual text overlay replaces the cells under it, background
-- included, so it has to carry the band's own)
local RULE = string.rep('─', 400)
local RULE_GROUP = 'OrgBlockRule'
local LABEL_GROUP = 'OrgBlockRuleLabel'

-- over render-markdown's own marks on a fence line (4096), so the rule
-- replaces the `▘ lua ████…` info row it draws there
local RULE_PRIORITY = 5000

-- the kinds org.nvim keeps as raw text (lua/org/ui/decorations.lua,
-- VERBATIM_BLOCKS): quote, verse, center and special blocks hold ordinary Org
-- text and get their own face instead.
local VERBATIM = { src = true, example = true, export = true, comment = true }

-- the `src` languages whose body is prose rather than code: the markdown
-- plugin renders the body (queries/org/injections.scm) and bands its fenced
-- code blocks
local PROSE = { markdown = true, md = true }

local pending = {}

-- what was last painted, per buffer: typing inside a block (most of what
-- `TextChangedI` sees) leaves the blocks where they were, and the extmarks --
-- one per row, the expensive part on a long file -- are not touched for
-- nothing.
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

--- A fence line of a markdown body: its indent, its backticks and the
--- language of its info string.
local function fence(line)
  local indent, ticks, info = line:match '^(%s*)(```+)(%S*)'
  return indent and #indent, ticks and #ticks, info
end

--- The rows of every snippet of `buf`, and the rule of each opening and
--- closing line.
---
--- `ranges` holds `{ first, last }` 0-based rows to band, `rules` holds
--- `{ row, col, label }` -- the label nil for a closing rule. Both a snippet's
--- own `#+begin_`/`#+end_` lines and the fences of a markdown body are ruled.
---@return { [1]: integer, [2]: integer }[] ranges, { [1]: integer, [2]: integer, [3]: string? }[] rules
local function scan(lines)
  local ranges, rules = {}, {}
  -- nil, 'band' (a snippet being banded) or 'prose' (a markdown body, banded by
  -- the markdown plugin, whose fences are ruled here)
  local mode, kind
  local first, open_col, open_label
  -- the column and the backticks of the open fence of a prose body
  local fence_col, fence_ticks

  for i, line in ipairs(lines) do
    local row = i - 1
    if mode == 'band' then
      if ends(line, kind) then
        ranges[#ranges + 1] = { first, row }
        rules[#rules + 1] = { row, #(line:match '^(%s*)'), nil }
        mode = nil
      elseif line:match '^%*+%s' then
        -- a headline ends a block (org.nvim's regions stop there too), so a
        -- block left unterminated is banded up to the line before it
        ranges[#ranges + 1] = { first, row - 1 }
        mode = nil
      end
    elseif mode == 'prose' then
      if ends(line, kind) or line:match '^%*+%s' then
        mode, fence_col = nil, nil
      elseif fence_col then
        -- a fence closes on its own width or more (` ``` ` never closes a
        -- ` ```` `), so a nested fence in the body does not cut it short
        local ticks = line:match '^%s*(```+)%s*$'
        if ticks and #ticks >= fence_ticks then
          rules[#rules + 1] = { row, fence_col, nil }
          fence_col = nil
        end
      else
        local col, ticks, info = fence(line)
        if col then
          fence_col, fence_ticks = col, ticks
          rules[#rules + 1] = { row, col, info ~= '' and info or nil }
        end
      end
    else
      local begin = begin_kind(line)
      if begin and VERBATIM[begin] then
        local lang = begin == 'src' and src_language(line)
        kind = begin
        if lang and PROSE[lang] then
          mode = 'prose'
        else
          mode, first = 'band', row
          open_col = #(line:match '^(%s*)')
          open_label = lang or kind
          rules[#rules + 1] = { row, open_col, open_label }
        end
      end
    end
  end
  -- nothing closed it: the band runs to the end of the buffer
  if mode == 'band' then
    ranges[#ranges + 1] = { first, #lines - 1 }
  end
  return ranges, rules
end

local function paint(buf)
  pending[buf] = nil
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    painted[buf] = nil
    return
  end
  local ranges, rules = scan(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if painted[buf] and vim.deep_equal(ranges, painted[buf][1]) and vim.deep_equal(rules, painted[buf][2]) then
    return
  end
  painted[buf] = { ranges, rules }
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, range in ipairs(ranges) do
    for row = range[1], range[2] do
      vim.api.nvim_buf_set_extmark(buf, NS, row, 0, { line_hl_group = BAND })
    end
  end
  for _, rule in ipairs(rules) do
    local virt_text = {}
    if rule[3] then
      virt_text[#virt_text + 1] = { '─ ' .. rule[3] .. ' ', LABEL_GROUP }
    end
    virt_text[#virt_text + 1] = { RULE, RULE_GROUP }
    vim.api.nvim_buf_set_extmark(buf, NS, rule[1], rule[2], {
      virt_text = virt_text,
      virt_text_pos = 'overlay',
      priority = RULE_PRIORITY,
    })
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
    desc = 'Band the org code snippets',
    callback = function(args)
      schedule(args.buf)
    end,
  })
  -- opening a new `#+begin_src`, closing one, or deleting a delimiter all
  -- change which rows belong to a snippet
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
