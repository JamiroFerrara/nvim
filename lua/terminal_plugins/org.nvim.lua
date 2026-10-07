-- Lives in terminal_plugins/ (imported in every launch) so org works in the
-- tmux `nvim +terminal` session that `alt+o` / t-script.sh opens, not only in
-- the full config: init.lua skips the whole plugins/ import when +terminal.
--
-- This file is only the plugin spec: options and the setup order of the
-- custom pieces, which live in lua/helpers/org/:
--   capture.lua     capture-task destination (level-1 project headlines)
--   ics.lua         iCalendar subscriptions + event-detail scratch viewer
--   cookies.lua     automatic statistics cookies and checkbox auto-DONE
--   agenda.lua      `D` toggle_done action and terminal-window takeover
--   decorations.lua checkbox icons (conceal, like the markdown config)
--   mappings.lua    buffer-local <CR> (normal/insert) and dd-on-headline
--   folding.lua     re-assert org folding after nvim-origami loads
--   cycle.lua       <S-Tab> folds to the buffer's #+STARTUP visibility
--   refile.lua      save the emptied store buffer after capture-refile
local ics = require 'helpers.org.ics'
local capture = require 'helpers.org.capture'

return {
  'xheisenbugx/org.nvim',
  main = 'org',
  lazy = false, -- startup cost is small: heavy modules load on first use
  opts = {
    org_directory = '~/org',
    agenda_files = { '~/org/**/*.org' },
    default_notes_file = '~/org/refile.org',
    -- The stock Task template (org.capture.templates DEFAULT_TEMPLATES.t)
    -- ends with `%a`, the annotation link back to the file/headline the
    -- capture was started from; it is dropped here. `target`/`headline`
    -- come from helpers/org/capture.lua: the picker asks for the level-1
    -- project headline the task belongs to, and the entry is stored under
    -- it right away. A configured `templates` table replaces the defaults
    -- rather than merging into them, so `t` is spelled out in full.
    capture = {
      templates = {
        t = {
          description = 'Task',
          type = 'entry',
          target = function()
            return capture.target()
          end,
          headline = function()
            return capture.headline()
          end,
          template = '* TODO %?\n  %u',
        },
      },
    },
    -- Same sequence as the old nvim-orgmode config (lua/plugins/org.lua at
    -- 630ef07^): TODO NEXT PEND TEST WARN | DONE. The project files use
    -- WARN/PEND/NEXT/TEST, which were plain text before.
    todo_keywords = { 'TODO NEXT PEND TEST WARN | DONE' },
    -- Refile targets. Left empty, `<prefix>r` only offers the level-1
    -- headlines of the buffer it starts in -- in refile.org that is just
    -- "Tasks", which is useless for sorting the inbox. Project files open
    -- with the project as their level-1 headline, so refiling downwards:
    --   Allitude (1) > Classificazioni EVO (2) > APB-860 (3) > ticket task
    -- `use_outline_path = 'file'` labels targets as
    -- "allitude.org/Allitude/Classificazioni EVO/APB-860" and also offers
    -- whole files as targets.
    refile = {
      targets = {
        { files = '~/org/projects/*.org', max_level = 3 },
        { files = '~/org/calendar/*.org', max_level = 1 },
        { files = 'current' },
      },
      use_outline_path = 'file',
    },
    ui = {
      -- Faces from the old config (org_todo_keyword_faces), same colors,
      -- but drawn the way the theme draws TODO/DONE: catppuccin links those
      -- (OrgTodo/OrgDone) to @comment.error / @comment.note, i.e. base text
      -- on a colored background. So the old colors go on :background with
      -- the palette's base as the text color.
      todo_keyword_faces = {
        NEXT = ':foreground #1e1e2e :background #89b4fa',
        PEND = ':foreground #1e1e2e :background #eed49f',
        WARN = ':foreground #1e1e2e :background #f5a97f',
        TEST = ':foreground #1e1e2e :background #94e2d5',
      },
      -- org.nvim's decorations are opt-in (bullets defaults to false, so the
      -- headline stars stay literal). Same glyphs as the markdown headings
      -- configured in plugins/markdown.lua (heading.icons); the level colors
      -- already match, org.nvim links OrgHeadlineLevelN to the theme's
      -- @markup.heading.N.markdown.
      bullets = (function()
        local nf = function(cp)
          return vim.fn.nr2char(cp, true)
        end
        return { nf(0x25cf), nf(0xf03a6), nf(0xf03a9), nf(0xf03ac), nf(0xf03ae), nf(0xf03b0) }
      end)(),
      -- Checkboxes replaced with icons, like the markdown checkboxes in
      -- plugins/markdown.lua: unchecked, partial (org's `[-]`), checked.
      checkboxes = (function()
        local nf = function(cp)
          return vim.fn.nr2char(cp, true)
        end
        return { nf(0xf096), nf(0xf138), nf(0xf14a) }
      end)(),
    },
    links = {
      -- <CR> on a file:/id: link replaces the current window
      frame_setup = { file = 'current' },
    },
    mappings = {
      -- Global actions, not buffer-local. pick_project_todo is
      -- helpers/org_todo.lua, registered as an action in the config
      -- function below (the pick_* actions ship with no default keys).
      -- Two steps: the projects (~/org/projects/*.org, by level-1
      -- headline), then the open TODOs of the chosen project.
      -- NOTE: inside org buffers `<prefix>s` is the buffer-local `schedule`
      -- (defaults, lua/org/config/mappings.lua) and shadows this.
      global = {
        pick_project_todo = '<prefix>s',
      },
      agenda = {
        -- next/previous span; J/K too. `f` is left to the global
        -- `f = /` mapping (lua/mappings.lua) so search works in the agenda
        later = 'J',
        earlier = { 'b', 'K' },
        clock_goto = '<C-c><C-x><C-j>',
        capture = '<C-c>k',
        -- <leader>n adds a timestamped note under the entry at point
        -- (org-add-note); the default `z` stays
        add_note = { 'z', '<leader>n' },
        -- `D` toggles the entry's state between DONE and TODO (the action
        -- is registered by helpers/org/agenda.lua in the config function
        -- below). It takes the place of the default `D` (toggle the Emacs
        -- diary), unbound here.
        toggle_done = 'D',
        toggle_diary = false,
        -- `|` quits like `q`, taking over the default `|` (remove the
        -- filter at point), unbound here
        quit = { 'q', '`' },
        filter_remove = false,
      },
      org = {
        -- <CR> on a checkbox item toggles it, elsewhere cycles visibility
        -- (helpers/org/mappings.lua); <Tab> keeps cycling
        cycle = '<Tab>',
        -- <leader>n adds a timestamped note under the headline at point
        -- (org-add-note). The Emacs key <C-c><C-z> keeps working.
        add_note = '<leader>n',
        -- next/previous visible heading on <C-j>/<C-k> (replaces ]]/[[).
        -- The action already jumps only to headings org.fold reports as
        -- visible, so a folded subtree is skipped. Buffer-local, so it
        -- shadows the global <C-j>/<C-k> (tmux pane / window) in org files.
        next_heading = '<C-j>',
        prev_heading = '<C-k>',
        -- move subtree / item / row / element on Alt+Up/Down only; <M-j> and
        -- <M-k> are the same keys as the global <A-j>/<A-k> tmux pane moves
        -- (lua/mappings.lua) and must keep doing that in org files
        meta_up = '<M-Up>',
        meta_down = '<M-Down>',
        -- link/footnote/date opening stays on gx / <prefix>o
        open_at_point = { 'gx', '<prefix>o' },
        -- <C-p> opens the project/TODO picker (helpers/org_todo.pick, the
        -- global <leader>os action -- which <prefix>s shadows with
        -- `schedule` in org buffers). Buffer-local, so it shadows the
        -- global fff <C-p> file finder in org files only; the agenda binds
        -- the same action in helpers/org/agenda.lua.
        pick_project_todo = '<C-p>',
        -- promote/demote on <S-h>/<S-l> (H/L) instead of <M-h>/<M-l>
        meta_left = { '<S-h>', '<M-Left>' },
        meta_right = { '<S-l>', '<M-Right>' },
        -- <S-Tab> folds to the buffer's #+STARTUP visibility when the
        -- header names one (show2levels .., content, showall, ...), else
        -- the default cycle (helpers/org/cycle.lua, registered below).
        -- <S-CR> keeps org.nvim's global cycle (OVERVIEW -> CONTENTS ->
        -- SHOW ALL).
        global_cycle_startup = '<S-Tab>',
        global_cycle = '<S-CR>',
        -- <S-CR> repurposed, so copy-table-field-down is disabled
        table_copy_down = false,
        -- ics actions have no default keys
        ics_refresh = '<prefix>cr',
        ics_import = '<prefix>ci',
        -- archive every top-level tree without an open TODO (on a
        -- headline: its children). Emacs reach is 4<prefix>$ (C-u C-c $);
        -- <prefix>$ alone still archives just the subtree at point.
        archive_all_done = '<prefix>D',
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
      -- kanban = {},
      lsp = {},
      -- cli = {},
      -- calendars live out of the repo; see helpers/org/ics.lua
      ics = { calendars = ics.calendars() },
      -- quickadd = {},
      super_agenda = {
        -- The "Today" group has two selectors (`date`, `time_grid`). A Lua
        -- group runs its selectors sorted by name, so `date` would list the
        -- timed entries and `time_grid` then append the bare grid rows below
        -- them. keep_order (= org-super-agenda-keep-order) sorts a group's
        -- items back into the agenda's time order, so grid lines interleave
        -- with the entries they mark, as Emacs does.
        keep_order = true,
        groups = {
          -- first match wins, in this list's order: the STIWIE calendar's
          -- events (ics diary items) must be claimed before Today (time
          -- grid) and Work (they carry the 'work' tag) can take them
          {
            name = 'GIGS',
            pred = function(it)
              return it.ics ~= nil and it.ics.calendar == 'STIWIE'
            end,
          },
          { name = 'Today', time_grid = true, date = 'today' },
          { name = 'Important', priority = 'A' },
          { name = 'Due soon', deadline = 'future', order = 2 },
          { name = 'Work', tag = { 'work', 'office' }, order = 1 },
          { discard = { tag = 'someday' } },
          { auto_category = true, order = 9 },
        },
      },
      -- roam = {},
      -- ql = {},
    },
  },
  -- ics events are injected into the agenda as read-only diary lines, so
  -- <CR> on one errors with "Command not allowed in this line". ics_import
  -- copies the event into an org file; :IcsPeek (helpers/org/ics.lua) shows
  -- it in a read-only scratch buffer instead, taking over the agenda window
  -- (q / <C-^> back).
  config = function(_, opts)
    -- The action registry is resolved by mappings and :Org at call time,
    -- so adding the entry before setup() makes mappings.global above bind
    -- it. helpers/org_todo.pick asks for a project, then its open TODOs.
    require('org.actions').list.pick_project_todo = {
      'helpers.org_todo',
      'pick',
      desc = 'Pick a project, then a TODO in it',
      global = true,
    }
    -- helpers/org/cycle.lua: <S-Tab> restores the #+STARTUP visibility
    -- when the buffer has one, else the default global cycle.
    require('org.actions').list.global_cycle_startup = {
      'helpers.org.cycle',
      'global_cycle',
      desc = "Fold to the buffer's #+STARTUP visibility (else cycle globally)",
    }
    require('org').setup(opts)

    -- Order matters where noted in the helpers: the FileType mappings must
    -- land after org.nvim attaches its own buffer mappings. setup() here is
    -- cheap: the helpers plug into org modules the plugin loads on first
    -- use through org.lazy.on_load (or plain autocmds), so no part of
    -- org.nvim is required at startup.
    require('helpers.org.agenda').setup()
    require('helpers.org.decorations').setup()
    require('helpers.org.mappings').setup()
    require('helpers.org.folding').setup()
    require('helpers.org.refile').setup()
    require('helpers.org.cookies').setup()
    require('helpers.org.ics').setup()
  end,
}
