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
