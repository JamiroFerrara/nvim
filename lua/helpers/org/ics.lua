-- iCalendar subscription support for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): the calendar list plus the agenda
-- scratch viewer for event details.
--
-- Subscriptions (Google Calendar and friends) are credentials: the Google
-- "secret address in iCal format" URL is a bearer secret, so it is kept out
-- of this repo in ~/.config/org/calendars.lua, which returns a list of
-- org.nvim calendar tables:
--   return {
--     { name = 'Google', url = 'https://calendar.google.com/calendar/ical/<id>/private-<token>/basic.ics' },
--     { name = 'Holidays', path = '~/cal/holidays.ics', category = 'Holiday' },
--   }
local M = {}

--- Calendar tables for `extensions.ics.calendars`, read from the
--- out-of-repo credentials file. Returns {} when it is missing or broken.
function M.calendars()
  local file = vim.fs.joinpath(vim.fn.expand '~/.config/org', 'calendars.lua')
  if vim.fn.filereadable(file) == 0 then
    return {}
  end
  local ok, calendars = pcall(dofile, file)
  if not ok then
    vim.schedule(function()
      vim.notify('org ics: ' .. tostring(calendars), vim.log.levels.ERROR)
    end)
    return {}
  end
  return type(calendars) == 'table' and calendars or {}
end

-- Most calendars (Google, Outlook) send the description as HTML. Pipe it
-- through lynx so the scratch shows text/tables, not markup; keep the
-- reference list, it carries the links. Falls back to a crude tag strip when
-- lynx is missing.
local function html_text(html)
  local cmd = {
    'lynx',
    '-dump',
    '-stdin',
    '-assume_charset=utf-8',
    '-display_charset=utf-8',
    '-width=' .. math.max(40, math.min(120, vim.o.columns - 4)),
  }
  local ok, res = pcall(function()
    return vim.system(cmd, { stdin = html, text = true }):wait()
  end)
  if ok and res.code == 0 and vim.trim(res.stdout or '') ~= '' then
    -- lynx resolves relative links against its temp file; drop that base
    return vim.trim((res.stdout:gsub('file:///%S*/lynx%w+/', '')))
  end
  local text = html:gsub('<[bB][rR]%s*/?>', '\n'):gsub('<[^>]->', ' '):gsub('&nbsp;', ' '):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&amp;', '&')
  return vim.trim(text)
end

local function lines_of(ev)
  local parts = {}
  local function add(label, v)
    if v and vim.trim(v) ~= '' then
      parts[#parts + 1] = label and (label .. ': ' .. vim.trim(v)) or vim.trim(v)
    end
  end
  add(nil, ev.summary)
  add('LOCATION', ev.location)
  add('URL', ev.url)
  local desc = vim.trim(ev.description or '')
  if desc ~= '' then
    if desc:find '<%a' then
      desc = html_text(desc)
    end
    parts[#parts + 1] = desc
  end
  return vim.split(table.concat(parts, '\n\n'), '\n', { plain = true })
end

-- Only reached from an agenda buffer, so the scratch takes over the agenda's
-- window; `q` goes back to the (hidden, bufhidden=hide) agenda.
local function open_scratch(lines, name)
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- descriptions are commonly HTML
  if table.concat(lines, '\n'):find '<%a' then
    vim.bo[buf].filetype = 'html'
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  pcall(vim.api.nvim_buf_set_name, buf, 'ics://' .. (name or 'event'):gsub('[%s/\\]', '_'))

  local saved = {}
  for _, o in ipairs { 'winbar', 'wrap', 'linebreak', 'number', 'relativenumber', 'signcolumn', 'foldenable', 'spell', 'list', 'cursorline' } do
    saved[o] = vim.wo[win][o]
  end
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].winbar = ' ics: ' .. (name or 'event'):gsub('%%', '%%%%')
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].foldenable = false
  vim.wo[win].spell = false
  vim.wo[win].list = false
  vim.wo[win].cursorline = false

  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        for o, v in pairs(saved) do
          vim.wo[win][o] = v
        end
      end
    end,
  })
  vim.keymap.set('n', 'q', function()
    vim.cmd 'buffer #'
  end, { buffer = buf, desc = 'ics: back to the agenda' })
end

local function peek(item)
  local ev = item and item.ics and item.ics.event
  if not ev then
    return false
  end
  open_scratch(lines_of(ev), ev.summary)
  return true
end

function M.setup()
  vim.api.nvim_create_user_command('IcsPeek', function()
    local view = require 'org.agenda.view'
    if not peek(vim.bo.filetype == 'orgagenda' and view.item_at_cursor() or nil) then
      vim.notify('ics: no calendar event on this line', vim.log.levels.WARN)
    end
  end, { desc = 'iCalendar event details of the agenda entry at the cursor' })

  -- <CR> (agenda.switch_to) on a calendar line opens the scratch instead of
  -- failing with "Command not allowed in this line"; on anything else it
  -- keeps its usual meaning.
  local switch_to_wrapped = false
  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'orgagenda',
    callback = function()
      if switch_to_wrapped then
        return
      end
      switch_to_wrapped = true
      local view = require 'org.agenda.view'
      local switch_to = view.actions.switch_to
      view.actions.switch_to = function()
        if not peek(view.item_at_cursor()) then
          return switch_to()
        end
      end
    end,
  })
end

return M
