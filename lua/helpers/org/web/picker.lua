-- The picker a run is standing on, driven from the page (helpers/org/web).
--
-- A run that asks a question waits on the picker inside its tmux pane: there
-- is no socket to answer it through, and the pane's keys are the only door.
-- So a click on the page is typed the way a person would type it -- the arrow
-- keys to the option it names, then `Enter` -- and every move is read back off
-- the pane before the key that commits it. A picker that has moved under the
-- click (the user answered in the pane, the run went on to the next question)
-- is then refused instead of answered with the wrong option.
--
-- What the pane shows is read, not assumed: the box the TUI draws (`╭─ Ask`)
-- holds the question, the options with the cursor on one of them, and a footer
-- that says whether the question takes one answer or several.
local M = {}

local STEP = 120 -- ms between two keys: the TUI redraws before the next
local COMMIT = 700 -- ms after the key that moves the picker on
local SCROLLBACK = '-120' -- lines above the visible pane that a box may begin

local GLYPHS = { '○', '◉', '☐', '☑' } -- the four the picker draws
local OTHER = 'Other (type your own)'

--- Run one tmux subcommand without a shell. Trimmed stdout, or nil plus what
--- tmux said.
---@param ... string
---@return string|nil
local function tmux(...)
  local out = vim.fn.system { 'tmux', ... }
  if vim.v.shell_error ~= 0 then
    return nil, (out or ''):gsub('%s+$', '')
  end
  return out
end

--- `text` without the spaces either end.
---@param text string
---@return string
local function trim(text)
  return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

--- The question a box is asking, as it is drawn: the lines between the top
--- border and the first rule, without the tab strip a round of several
--- questions carries (it is the one that starts two spaces in).
---@param lines string[]
---@param top integer
---@return string
local function question_below(lines, top)
  local out = {}
  for i = top + 1, #lines do
    if lines[i]:match '^├' then
      break
    end
    local inner = lines[i]:match '^│(.*)│%s*$'
    if inner and not inner:match '^  %S' and inner:match '%S' then
      out[#out + 1] = trim(inner)
    end
  end
  return table.concat(out, '\n')
end

--- The picker showing in `pane`, or nil when the pane is not on one.
---
--- `custom` marks the editor the picker opens for `Other (type your own)`,
--- whose title carries the question instead of a row of options.
---@param pane string
---@return table|nil box { question, options, cursor, multi, custom }
function M.read(pane)
  local text = tmux('capture-pane', '-p', '-t', pane, '-S', SCROLLBACK)
  if not text then
    return nil
  end
  local lines = vim.split(text, '\n', { plain = true })
  local top, title
  for i = #lines, 1, -1 do
    local name = lines[i]:match '^╭─ ([^─]+) '
    if name and (name == 'Ask' or name:match '^Custom answer') then
      top, title = i, name
      break
    end
  end
  if not top then
    return nil
  end
  if title:match '^Custom answer' then
    local asked = title:match '^Custom answer:%s*(.-)%.?$'
    return { question = asked or '', options = {}, cursor = 0, multi = false, custom = true }
  end
  local options, cursor, footer = {}, 0, ''
  local section = 0 -- the content above the first rule, then the options, then the footer
  for i = top + 1, #lines do
    local line = lines[i]
    if line:match '^╰' then
      break
    end
    if line:match '^├' then
      section = section + 1
    elseif section == 1 then
      local inner = line:match '^│(.*)│%s*$'
      local at, glyph
      for _, mark in ipairs(GLYPHS) do
        local pos = inner and inner:find(mark, 1, true)
        if pos and (not at or pos < at) then
          at, glyph = pos, mark
        end
      end
      if glyph then
        local label = trim(inner:sub(at + #glyph)):gsub('%s*%(Recommended%)$', '')
        options[#options + 1] = { label = label, picked = glyph == '◉' or glyph == '☑' }
        if inner:find('❯', 1, true) then
          cursor = #options
        end
      end
    elseif section >= 2 and line:match '^│' then
      footer = footer .. line
    end
  end
  return {
    question = question_below(lines, top),
    options = options,
    cursor = cursor,
    multi = footer:find('toggle', 1, true) ~= nil,
    custom = false,
  }
end

--- Whether two pieces of text are the same question: the picker wraps and
--- clips what it draws, so the first 40 characters decide.
---@param a string|nil
---@param b string|nil
---@return boolean
local function same_question(a, b)
  local norm = function(text)
    return trim((tostring(text or ''):gsub('%s+', ' '):lower()))
  end
  a, b = norm(a), norm(b)
  if a == '' or b == '' then
    return false
  end
  return vim.fn.strcharpart(a, 0, 40) == vim.fn.strcharpart(b, 0, 40)
end

--- The row of `box` offering `label`, or nil. A long label is clipped by the
--- pane, so a row that is a long enough beginning of the label counts.
---@param box table
---@param label string
---@return integer|nil
local function row_of(box, label)
  local found
  for i, option in ipairs(box.options) do
    local shown = option.label
    if shown == label or (#shown >= 16 and label:sub(1, #shown) == shown) then
      if found then
        return nil -- two rows it could be: refuse rather than guess
      end
      found = i
    end
  end
  return found
end

--- Press `key` in `pane` and let the TUI redraw.
---@param pane string
---@param key string
---@param wait integer|nil
local function press(pane, key, wait)
  tmux('send-keys', '-t', pane, key)
  vim.wait(wait or STEP)
end

--- Answer the question the run in `pane` is standing on.
---
--- `answer.question` is which question the click was made on, `answer.label`
--- the option it names (or `answer.labels` for a question that takes several),
--- `answer.custom` the words to type into the picker's own editor.
---@param pane string
---@param answer table
---@return boolean ok, string|nil error
function M.answer(pane, answer)
  answer = type(answer) == 'table' and answer or {}
  if type(pane) ~= 'string' or not pane:match '^%%%d+$' then
    return false, 'no such run'
  end
  local box = M.read(pane)
  if not box then
    return false, 'the run is not asking anything'
  end
  if box.custom or not same_question(box.question, answer.question) then
    return false, 'the run is not on that question any more'
  end
  local labels = {}
  if type(answer.custom) == 'string' and answer.custom:match '%S' then
    labels = { OTHER }
  elseif type(answer.labels) == 'table' then
    labels = answer.labels
  elseif type(answer.label) == 'string' then
    labels = { answer.label }
  end
  for _, label in ipairs(labels) do
    if type(label) ~= 'string' or not label:match '%S' then
      return false, 'no answer was named'
    end
  end
  if #labels == 0 then
    return false, 'no answer was named'
  end
  local multi = box.multi and type(answer.custom) ~= 'string'
  if multi then
    -- a question that takes several answers starts from whatever is ticked
    -- already: the click names the whole answer, so a tick it does not name
    -- has to come off as well
    for i, option in ipairs(box.options) do
      if option.label ~= OTHER then
        local wanted = false
        for _, label in ipairs(labels) do
          wanted = wanted or row_of(box, label) == i
        end
        if option.picked and not wanted then
          local cursor = box.cursor
          for _ = 1, math.abs(i - cursor) do
            press(pane, i > cursor and 'Down' or 'Up')
          end
          box = M.read(pane)
          if not box or box.custom or box.cursor ~= i then
            return false, 'the picker did not take the move'
          end
          press(pane, 'Space')
          box = M.read(pane)
          if not box or box.custom then
            return false, 'the picker did not take the move'
          end
        end
      end
    end
  end
  for _, label in ipairs(labels) do
    local target = row_of(box, label)
    if not target then
      return false, ('the picker offers no "%s"'):format(label)
    end
    if multi and box.options[target].picked then
      target = nil -- already ticked: only a multi-select question has these
    end
    if target then
      local cursor = box.cursor
      for _ = 1, math.abs(target - cursor) do
        press(pane, target > cursor and 'Down' or 'Up')
      end
      box = M.read(pane)
      if not box or box.custom or box.cursor ~= target then
        return false, 'the picker did not take the move'
      end
      if multi then
        press(pane, 'Space')
        box = M.read(pane)
        if not box or box.custom then
          return false, 'the picker did not take the move'
        end
      end
    end
  end
  local custom = type(answer.custom) == 'string' and answer.custom:match '%S'
  press(pane, 'Enter')
  vim.wait(COMMIT - STEP)
  if custom then
    local editor = M.read(pane)
    if not editor or not editor.custom then
      return false, 'the picker did not open its editor'
    end
    tmux('send-keys', '-t', pane, '-l', answer.custom)
    vim.wait(STEP)
    press(pane, 'Enter')
    vim.wait(COMMIT - STEP)
  end
  local after = M.read(pane)
  -- a round of several questions ends on its own review step: the answers
  -- are not the run's until that one is sent too
  if after and not after.custom and after.question:match '^Review answers' then
    press(pane, 'Enter')
    vim.wait(COMMIT - STEP)
    after = M.read(pane)
  end
  if after and not after.custom and same_question(after.question, answer.question) then
    return false, 'the picker is still on that question'
  end
  return true
end

return M
