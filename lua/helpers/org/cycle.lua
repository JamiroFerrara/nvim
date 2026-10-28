-- <Tab> on an entry is a toggle: org.nvim's cycle is folded -> CHILDREN ->
-- SUBTREE -> folded, so the press that opens an entry (CHILDREN) leaves two
-- more before it closes again. Here the entry the previous <Tab> left in
-- CHILDREN folds on the next one, so unfolding and folding cost a press each
-- (wired in lua/terminal_plugins/org.nvim.lua as the `cycle` action). The
-- SUBTREE state is kept on a count -- `<N><Tab>` shows the subtree of the
-- ancestor at level N, `16<Tab>` the startup visibility, `64<Tab>` everything.
--
-- <S-Tab> global visibility that honours the buffer's #+STARTUP (wired in
-- lua/terminal_plugins/org.nvim.lua as the `global_cycle_startup` action).
-- With a folding mode in the header (show2levels .. show5levels, content,
-- overview, showall, showeverything, nofold) <S-Tab> restores exactly that
-- visibility, the same as when the buffer is first loaded -- hidedrawers,
-- hideblocks and `VISIBILITY` properties included, so `#+STARTUP: show2levels
-- logdone logdrawer` shows two levels with LOGBOOK drawers folded. Without
-- such a word the key falls through to org.nvim's own global cycle
-- (OVERVIEW -> CONTENTS -> SHOW ALL). A count N is left to org.nvim (show
-- the headlines with up to N levels).
local M = {}

-- Mirrors STARTUP_MODES in org.fold.helpers (which is local to the plugin).
local STARTUP_MODES = {
  'overview',
  'content',
  'showall',
  'showeverything',
  'nofold',
  'fold',
  'show2levels',
  'show3levels',
  'show4levels',
  'show5levels',
}

--- Whether the buffer's #+STARTUP names the visibility to fold to.
local function has_visibility(startup)
  for _, word in ipairs(STARTUP_MODES) do
    if startup[word] then
      return true
    end
  end
  return false
end

--- `<Tab>` on an entry the previous `<Tab>` left in the CHILDREN state folds
--- it instead of cycling on to SUBTREE, so the two states toggle. Every other
--- case -- an entry folded or already unfolded some other way, a list item,
--- a drawer, a block, a table, a plain line, a link, a count -- is org.nvim's
--- own cycle.
function M.cycle()
  local fold = require 'org.fold'
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local last = vim.w.org_last_cycle
  if
    vim.v.count == 0
    and last
    and last.status == 'children'
    and last.buf == vim.api.nvim_get_current_buf()
    and last.lnum == lnum
    and last.tick == vim.api.nvim_buf_get_changedtick(0)
    and vim.fn.foldclosed(lnum) == -1
    and vim.fn.foldlevel(lnum) > 0
  then
    local shared = require 'org.fold.shared'
    shared.run_cycle_hook('OrgCyclePre', 'folded', lnum)
    shared.close_at(lnum)
    shared.refresh_ellipsis()
    vim.w.org_last_cycle = { buf = last.buf, lnum = lnum, tick = last.tick, status = 'folded' }
    shared.run_cycle_hook('OrgCycle', 'folded', lnum)
    vim.api.nvim_echo({ { 'FOLDED' } }, false, {})
    return
  end
  return fold.cycle()
end

function M.global_cycle()
  local fold = require 'org.fold'
  if vim.v.count > 0 then
    return fold.global_cycle()
  end
  local _, startup = require('org.fold.shared').startup_mode(0)
  if not has_visibility(startup) then
    return fold.global_cycle()
  end
  -- apply_startup(0), plus the message C-u C-u <Tab> shows
  return fold.set_startup_visibility()
end

return M
