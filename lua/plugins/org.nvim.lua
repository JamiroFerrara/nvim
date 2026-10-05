-- iCalendar subscriptions (Google Calendar and friends) are credentials: the
-- Google "secret address in iCal format" URL is a bearer secret, so it is kept
-- out of this repo in ~/.config/org/calendars.lua, which returns a list of
-- org.nvim calendar tables:
--   return {
--     { name = 'Google', url = 'https://calendar.google.com/calendar/ical/<id>/private-<token>/basic.ics' },
--     { name = 'Holidays', path = '~/cal/holidays.ics', category = 'Holiday' },
--   }
local function ics_calendars()
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

return {
  'xheisenbugx/org.nvim',
  main = 'org',
  lazy = false, -- startup cost is small: heavy modules load on first use
  opts = {
    org_directory = '~/org',
    agenda_files = { '~/org/**/*.org' },
    default_notes_file = '~/org/refile.org',
    links = {
      -- <CR> on a file:/id: link replaces the current window
      frame_setup = { file = 'current' },
    },
    mappings = {
      org = {
        -- <CR> cycles visibility like <Tab>
        cycle = { '<Tab>', '<CR>' },
        -- link/footnote/date opening stays on gx / <prefix>o
        open_at_point = { 'gx', '<prefix>o' },
        -- promote/demote on <S-h>/<S-l> (H/L) instead of <M-h>/<M-l>
        meta_left = { '<S-h>', '<M-Left>' },
        meta_right = { '<S-l>', '<M-Right>' },
        -- <S-CR> cycles global visibility like <S-Tab>
        global_cycle = { '<S-Tab>', '<S-CR>' },
        -- <S-CR> repurposed, so copy-table-field-down is disabled
        table_copy_down = false,
        -- ics actions have no default keys
        ics_refresh = '<prefix>cr',
        ics_import = '<prefix>ci',
      },
      org_insert = {
        -- <CR> acts like <Tab>: next table field / cycle empty heading level
        insert_tab = { '<Tab>', '<CR>' },
        table_next_row = false,
        -- <S-CR> goes to previous table field like <S-Tab>
        table_prev_field = { '<S-Tab>', '<S-CR>' },
        table_copy_down = false,
      },
    },
    extensions = {
      sidebar = {},
      -- heatmap = {},
      kanban = {},
      -- lsp = {},
      -- cli = {},
      -- calendars described at the top of this file
      ics = { calendars = ics_calendars() },
      -- quickadd = {},
      super_agenda = {},
      -- roam = {},
      -- ql = {},
    },
  },
}
