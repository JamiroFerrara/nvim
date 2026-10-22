-- Content tags for captured entries: the words a capture says decide its
-- tags at store time. A rule maps one word to one tag, and an entry whose
-- own text -- its headline, then the lines typed under it -- carries that
-- word lands the tag on its headline, so "fix the crash in the picker"
-- stores `:bug:` without a keypress.
--
-- The map is the `autotags` of the plugin's capture options
-- (lua/terminal_plugins/org.nvim.lua). A project file replaces it for
-- itself with the file keyword
--
--   #+AUTOTAGS: bug=bug crash=bug feature=feat
--
-- Entries are `word=tag` (a bare `word` is its own tag), separated like
-- org's file lists, by whitespace or commas, so a key is one token. The
-- keyword replaces the default map wholesale -- a file that names one rule
-- has one rule -- and a bare `#+AUTOTAGS:` disables the tagging there. The
-- destination of the capture decides, the same file the entry lands in: a
-- rule is a fact about a board's vocabulary, and every capture path goes
-- through the same destination.
--
-- A word is matched case-insensitively as a whole word (`bug` matches
-- "Bug" and "bug", never "debug" or "bugfix"): a substring rule would tag
-- every debugging note `:bug:`, and the map cannot see intent. The entry's
-- own text is what it scans -- the headline and the typed body -- never the
-- date header or the annotation link back to the origin, which belong to
-- other entries.
local M = {}

--- Rules `word -> tag` from a `#+AUTOTAGS:` value, or nil when the value
--- names nothing (a bare keyword).
---@param value string
---@return table<string, string>|nil
local function parse(value)
  local out = {}
  for entry in value:gmatch '[^%s,]+' do
    local word, tag = entry:match '^(.-)=(.+)$'
    out[word or entry] = tag or entry
  end
  return next(out) and out or nil
end

--- The rules in force for a capture into `file`: the file's `#+AUTOTAGS:`
--- when it has one (its rules replace the defaults, a bare keyword leaves
--- none), else the configured default map.
---@param file? table
---@return table<string, string>
function M.rules(file)
  local keywords = file and file.settings and file.settings.keywords
  local values = keywords and keywords.AUTOTAGS
  if not values then
    return require('org.config').opts.capture.autotags or {}
  end
  local out = {}
  for _, value in ipairs(values) do
    for word, tag in pairs(parse(value) or {}) do
      out[word] = tag
    end
  end
  return out
end

--- Whether `word` appears in `text` as a whole word, case-insensitively.
---@param text string lowercased text
---@param word string
---@return boolean
local function has_word(text, word)
  return text:find('%f[%w]' .. vim.pesc(word:lower()) .. '%f[%W]') ~= nil
end

--- The entry's text: every line but the date header and a bare link line
--- (the annotation `%a` back to the origin), lowercased.
---@param lines string[]
---@return string
local function text_of(lines)
  local parts = {}
  for _, l in ipairs(lines) do
    if not l:match '^%s*%[[%d%-]+%s+%a%a%a[^%]]*%] %-+%s*$' and not l:match '^%s*%[%[.-%]%]%s*$' then
      parts[#parts + 1] = l
    end
  end
  return table.concat(parts, '\n'):lower()
end

--- org.nvim store filter: tag the captured entry with every rule its own
--- text matches, appended to the tags it already carries. Entry captures
--- only; returns nil when nothing matched or nothing changed.
---@param tpl table
---@param lines string[]
---@param ctx table
---@return string[]|nil
function M.filter(tpl, lines, ctx)
  if (tpl.type or 'entry') ~= 'entry' then
    return nil
  end
  ctx = ctx or {}
  local rules = M.rules(ctx.target_file)
  if not next(rules) then
    return nil
  end
  local text = text_of(lines)
  local tags, seen = {}, {}
  for word, tag in pairs(rules) do
    if not seen[tag] and has_word(text, word) then
      seen[tag] = true
      tags[#tags + 1] = tag
    end
  end
  if #tags == 0 then
    return nil
  end
  table.sort(tags)
  return require('helpers.org.capture').add_tags(lines, ctx.target_file, tags)
end

return M
