-- Lives in terminal_plugins/ (imported in every launch) so org works in the
-- tmux `nvim +terminal` session that `alt+o` / t-script.sh opens, not only in
-- the full config: init.lua skips the whole plugins/ import when +terminal.
--
-- This file is only the plugin spec: options and the setup order of the
-- custom pieces, which live in lua/helpers/org/:
--   capture.lua     capture-task destination (level-1 project headlines)
--   ics.lua         iCalendar subscriptions + event-detail scratch viewer
--   cookies.lua     automatic statistics cookies and checkbox auto-DONE
--   agenda.lua      `D` toggle_done action, the fold state after entering
--                   an entry from the list, and the insert mode a terminal
--                   window would leave in the agenda
--   decorations.lua checkbox icons (conceal, like the markdown config)
--   mappings.lua    buffer-local <CR> (normal/insert), dd-on-headline,
--                   the capture keys in insert mode, and insert mode back
--                   when the capture buffer is entered again
--   folding.lua     re-assert org folding after nvim-origami loads, and
--                   fold to the buffer's #+STARTUP on a jump from the list
--   cycle.lua       <S-Tab> folds to the buffer's #+STARTUP visibility
--   refile.lua      save the emptied store buffer after capture-refile
--   notes.lua       notes land in the entry body (newest first, timestamp +
--                   rule header) instead of a LOGBOOK drawer, and saving
--                   the note buffer stores it
--   ai.lua          <leader>ai on an entry launches an `omp` instance for
--                   the ticket in a tmux pane and follows its write-back
--                   (reload changed org files on FocusGained)
local ics = require 'helpers.org.ics'
local capture = require 'helpers.org.capture'
local notes = require 'helpers.org.notes'

return {
  'xheisenbugx/org.nvim',
  main = 'org',
  lazy = false, -- startup cost is small: heavy modules load on first use
  opts = {
    org_directory = '~/org',
    agenda_files = { '~/org/**/*.org' },
    default_notes_file = '~/org/refile.org',
    -- org.nvim can remind you about timed entries: SCHEDULED, DEADLINE and
    -- plain timestamps in the agenda files fire a vim.notify -- and, with
    -- system_notification, a desktop toast -- before they start. It is the
    -- only notification org.nvim ships, it reads the whole global agenda file
    -- set (`agenda_files`), and it is the "org mode notification" that would
    -- pop up over the agenda. Already off by default, pinned off so nothing
    -- (:Org notifications_start included) turns it back on.
    notifications = { enabled = false },
    -- Where the agenda opens: the focused window (Emacs
    -- org-agenda-window-setup "current-window"), so `§` / `<leader>ot` /
    -- `°` take over the buffer that has focus -- a terminal window
    -- included, where helpers/org/agenda.lua only has to undo the
    -- startinsert its autocommands run -- and `q` puts the previous buffer
    -- back (agenda.restore_windows_after_quit stays false). Was "split":
    -- the agenda landed in a window below and view/window.lua ran
    -- `silent! only` first, throwing the layout away.
    agenda = {
      window = 'current',
      -- Write the source buffer after every edit made from the view (TODO
      -- state, priority, tags, dates, notes...). Emacs leaves them modified
      -- (org.nvim's default, `save_after_edit = false`); here a change from
      -- the view writes the file. The `°` TODO view renders into the same
      -- orgagenda buffer, so this is what makes changing a TODO there save
      -- the project file instead of leaving it dirty in the background.
      save_after_edit = true,
      -- Cross-project roll-ups: every other view (agenda_files, `°`, the
      -- TODO picker) reads one project, so the tags and priorities the
      -- ticket lines already carry are only visible here. Reached from the
      -- dispatcher menu or `:Org agenda <key>`, which give the whole set;
      -- the agenda buffer's 1 / 2 / 3 / 4 / 5 (helpers/org/agenda.lua) open
      -- them, 1 global and the rest narrowed to the cwd's project. The keys
      -- avoid the built-in dispatcher ones (a t T m M s S n # / < > e * ?), so
      -- they add rows instead of replacing. Blocks are `tags_todo` (tags/
      -- property match, TODO entries only) -- the `/!` trailing the match is
      -- the TODO part of |org-match-syntax|, "not done". `o` is every open
      -- TODO (`type = 'todo'`, org's `alltodo`), `b` pulls the bug tag and the
      -- WARN keyword, `f` the feat tag, `d` the DONE keyword (a `todo` block,
      -- not `tags_todo`, so the finished entries are listed, not filtered
      -- out), `p` the open A/B priorities. A block's `header` labels the
      -- group; a composite command shows its blocks one after the other, in
      -- this order.
      custom_commands = {
        o = {
          description = 'All open TODOs',
          types = {
            { type = 'todo', header = 'All open TODOs' },
          },
        },
        b = {
          description = 'Bugs and warnings',
          types = {
            { type = 'tags_todo', match = 'bug/!', header = 'Tagged bug, open' },
            { type = 'todo', match = 'WARN', header = 'WARN' },
          },
        },
        f = {
          description = 'Features',
          types = {
            { type = 'tags_todo', match = 'feat/!', header = 'Tagged feat, open' },
          },
        },
        d = {
          description = 'Done items',
          types = {
            { type = 'todo', match = 'DONE', header = 'Done' },
          },
        },
        p = {
          description = 'Open A/B priorities',
          types = {
            { type = 'tags_todo', match = 'PRIORITY="A"/!', header = 'Priority A, open' },
            { type = 'tags_todo', match = 'PRIORITY="B"/!', header = 'Priority B, open' },
          },
        },
      },
      -- Emacs' org-agenda-show-outline-path: echo the outline path of the
      -- entry at point on every cursor move. Off here, because org.nvim
      -- echoes it as a message and Neovim answers any message wider than the
      -- window with the hit-enter prompt (`Press ENTER or type command to
      -- continue`), which then eats the next `j` / `k`. Launching an omp
      -- instance splits the tmux window, so every ticket line -- the long
      -- ones a project file is full of -- is wider than what nvim has left.
      -- The entry line already carries the category, and the `°` TODO view
      -- reads one project, so the path said little anyway.
      show_outline_path = false,
    },
    -- The stock Task template (org.capture.templates DEFAULT_TEMPLATES.t)
    -- ends with `%a`, the annotation link back to the file/headline the
    -- capture was started from; it is dropped here. `target`/`olp` come from
    -- helpers/org/capture.lua: the working directory decides the project
    -- first (helpers/org/project.lua), so the entry goes straight under that
    -- project's headline -- a headline of a shared file included, which is
    -- why the destination is an outline path and not a title. Only a cwd
    -- that names no project opens the picker for it. A configured
    -- `templates` table replaces the defaults rather than merging into them,
    -- so `t` is spelled out in full.
    capture = {
      templates = {
        t = {
          description = 'Task',
          type = 'entry',
          target = function()
            return capture.target()
          end,
          olp = function()
            return capture.olp()
          end,
          template = '* TODO %?\n  %u ' .. string.rep('-', notes.DASHES),
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
      -- The cwd decides first (helpers/org/project.lua): with a project it
      -- jumps straight to that project's open TODOs, otherwise the two-step
      -- picker runs: the projects (~/org/projects/*.org, by level-1
      -- headline), then the TODOs of the chosen one.
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
        -- `N` cycles the TO-DO keyword of the entry at point (TODO -> NEXT
        -- -> PEND -> TEST -> WARN -> DONE -> none), like <C-S-Right>; the
        -- same keys reach the TODO view, which renders into an orgagenda
        -- buffer too.
        todo_next = { '<C-S-Right>', 'N' },
        -- `t` adds/edits the tags of the entry at point (org-set-tags: the
        -- fast-selection menu, where <Tab> types one with completion). It
        -- takes over the default `t` (org-agenda-todo, a fast state
        -- selection) -- `D` toggles DONE and `N` cycles the keyword already
        -- -- but keeps the Emacs key <C-c><C-t> on the state selection.
        -- Reaches the TODO view too, which renders into an orgagenda
        -- buffer. The default `:` and the <C-c><C-q> / <C-c><C-c>
        -- spellings stay on set_tags.
        todo = '<C-c><C-t>',
        set_tags = { 't', ':', '<C-c><C-q>', '<C-c><C-c>' },
        -- `p` sets the priority of the entry at point (org-priority: prompt
        -- for a value, SPC removes it). The default `p` (previous item) is
        -- unbound here so it cannot win the key -- both would bind it, in
        -- table order. `n` still steps forward and `J` / `K` move by day.
        -- The Emacs keys `,` and <C-c>, stay. Reaches the TODO view, which
        -- renders into the same orgagenda buffer.
        priority = { 'p', ',', '<C-c>,' },
        prev_item = false,
        -- `|` quits like `q`, taking over the default `|` (remove the
        -- filter at point), unbound here
        quit = { 'q', '`' },
        filter_remove = false,
        -- `^` is the global org capture key (lua/mappings.lua). The default
        -- agenda `^` (filter to the top headline) would shadow it in the
        -- agenda and in the TODO view, which renders into the same buffer.
        filter_top_headline = false,
      },
      -- Capture buffer keys. The defaults stay: finalize <C-c><C-c> /
      -- <prefix>w, kill <C-c><C-k> / <prefix>k, refile <C-c><C-w> /
      -- <prefix>r.
      capture = {
        -- <C-s> is the insert-mode save key (lua/mappings.lua); `:w` files
        -- the capture through org.nvim's BufWriteCmd hook, so the key files
        -- it from insert mode already. Bind it in normal mode too, so
        -- saving files the capture whichever mode the cursor is in.
        finalize = { '<C-c><C-c>', '<prefix>w', '<C-s>' },
        -- `q` aborts the capture and closes its window instead of starting
        -- a macro recording. Normal mode only: helpers/org/mappings.lua
        -- mirrors just the <C-c>-prefixed keys in insert mode, so a typed
        -- `q` stays a character.
        kill = { '<C-c><C-k>', '<prefix>k', 'q' },
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
        -- promote/demote on <C-h>/<C-l> instead of <M-h>/<M-l>
        meta_left = { '<C-h>', '<M-Left>' },
        meta_right = { '<C-l>', '<M-Right>' },
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
        -- Grouping runs once per rendered unit: the grouper hook is called
        -- per day block for an agenda view (with that day's number) and once
        -- for a list block, so a group with a fixed name prints its header
        -- under *every* day of a week view. The time-grid group therefore
        -- has no name: its job is to hold the timed entries and the grid
        -- pseudo-rows (which otherwise fall into "Other items" and lose
        -- their interleaving), not to label the day. The day sections and
        -- the `← now` line already say which day is today.
        --
        -- A group's selectors take their items in turn (an implicit OR), so
        -- `time_grid = true, date = 'today'` means "timed items, plus
        -- anything dated today". keep_order (= org-super-agenda-keep-order)
        -- sorts a group's items back into agenda order, so the grid lines
        -- interleave with the entries they mark, as Emacs does.
        keep_order = true,
        groups = {
          -- first match wins, in this list's order: the STIWIE calendar's
          -- events (ics diary items) must be claimed before the time-grid
          -- group and Work (they carry the 'work' tag) can take them
          {
            name = 'GIGS',
            pred = function(it)
              return it.ics ~= nil and it.ics.calendar == 'STIWIE'
            end,
          },
          { name = false, time_grid = true, date = 'today' },
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
      desc = 'Jump to a TODO of the current project (else pick a project)',
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
    require('helpers.org.notes').setup()
    require('helpers.org.mappings').setup()
    require('helpers.org.folding').setup()
    require('helpers.org.refile').setup()
    require('helpers.org.cookies').setup()
    require('helpers.org.ics').setup()
    require('helpers.org.ai').setup()
  end,
}
