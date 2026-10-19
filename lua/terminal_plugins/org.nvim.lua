-- Lives in terminal_plugins/ (imported in every launch) so org works in the
-- tmux `nvim +terminal` session that `alt+o` / t-script.sh opens, not only in
-- the full config: init.lua skips the whole plugins/ import when +terminal.
--
-- This file is only the plugin spec: options and the setup order of the
-- custom pieces, which live in lua/helpers/org/:
--   project.lua     cwd -> the project it belongs to: directories are claimed
--                   by a `#+PROJECT_DIRS:` file keyword and by the
--                   `:PROJECT_DIRS:` property of a headline, so one file can
--                   host several projects; the longest covering prefix wins
--                   (a headline claim beating the file's on a tie), else the
--                   nearest `.git` root. The capture destination, the
--                   project-scoped views and the `^` write side use it
--   capture.lua     capture under a headline (`c`, and the capture-task
--                   destination of level-1 project headlines)
--   ics.lua         iCalendar subscriptions + event-detail scratch viewer
--   cookies.lua     automatic statistics cookies, the checkbox auto-DONE,
--                   the auto-DONE of an entry whose child headlines are all
--                   finished, and the reopen of a finished parent when a
--                   capture files an open entry under it
--   agenda.lua      `D` toggle_done action, the `<CR>` entry scratch (a
--                   TODO view's checkbox line takes `<CR>` for the toggle,
--                   helpers/org/tree.lua) and
--                   the `L` preview pane beside the view, the fold state
--                   after entering an entry from the list, and the insert
--                   mode a terminal window would leave in the agenda
--   tagging.lua     one-key tag/priority toggles (B/F/C, <M-a>/<M-b>/<M-c>)
--                   in org buffers and, via agenda.lua, in the view
--   decorations.lua checkbox icons (conceal, like the markdown config)
--   mappings.lua    buffer-local <CR> (normal/insert): follow the link
--                   under the cursor, else toggle/make a checkbox or
--                   fold a headline; dd-on-headline, `c`-on-headline
--                   capture (else the change operator),
--                   the capture keys in insert mode, and insert mode back
--                   when the capture buffer is entered again
--   folding.lua     re-assert org folding after nvim-origami loads, and
--                   fold to the buffer's #+STARTUP on a jump from the list
--   cycle.lua       <S-Tab> folds to the buffer's #+STARTUP visibility
--   refile.lua      save the emptied store buffer after capture-refile
--   notes.lua       notes land in the entry body (appended at the end,
--                   timestamp + rule header) instead of a LOGBOOK drawer,
--                   so an entry reads as a chronological log, and saving
--                   the note buffer stores it
--   changed.lua     the "last changed" date column of the TODO-entry lists,
--                   read per entry through the todo `prefix_format` below,
--                   plus the `changed-up` / `changed-down` sorting strategies
--                   (the group view's sections)
--   ai.lua          <leader>ai on an entry launches an `omp` instance for
--                   the ticket in a tmux pane and follows its write-back
--                   (watch.lua reloads the changed org files live; the
--                   FocusGained autocmd covers a change made while nvim
--                   was unfocused). A group node -- a headline with
--                   subnodes in todo -- fans out to those subnodes, one
--                   instance each. In an open capture buffer the same key
--                   files the capture at its destination first and launches
--                   on the entry it stored
--   retro.lua       `<leader>ar`: one omp run over the agent sessions of
--                   every DONE ticket carrying `:OMP_SESSION:`, the retro
--                   skill appended; the report lands in a dated file under
--                   the nvim data directory
--   watch.lua       fs_event watcher over the org tree: reloads changed
--                   org buffers and re-renders the agenda view whenever an
--                   org file changes on disk, focus aside
--   tree.lua        TODO views as trees: an entry's listed sublevels, its
--                   plain (not TODO) subheadlines and its checkbox items are
--                   nested under it with tree guides, folded at level 1,
--                   <Tab>/<S-Tab> fold like an org file, `c` / <leader>aC
--                   capture a child of the entry at point, and <CR> on a
--                   checkbox line toggles that box in the entry's own file
--                   (everywhere else <CR> stays the entry scratch)
--   callouts.lua    entry lines of the TODO views get a callout bar in the
--                   state's color (from the keyword face), in the left
--                   gutter only -- no background band behind the line
--   actions.lua     `<leader>oM`: a fuzzy picker over what org can do in
--                   the buffer it is pressed in -- the entry at point, the
--                   view's own keys, org.nvim's registry and the two view
--                   toggles (agenda.lua) -- each entry run through the
--                   very function its own key runs
--   roam_cmp.lua    the nvim-cmp source for roam `[[` links (wired in
--                   lua/plugins/cmp.lua, not here): typing `[[` in a roam
--                   file completes node titles and aliases, and creates the
--                   node when the typed text is not one -- obsidian.nvim's
--                   `[[` completion, for the org vault

local ics = require 'helpers.org.ics'
local capture = require 'helpers.org.capture'
local notes = require 'helpers.org.notes'

-- TODO keyword sequence (org-todo-keywords): the keywords before the `|` are
-- open, the ones after it done. Named here rather than inline in
-- `todo_keywords` because the board's per-state sections (`w` below) are
-- derived from the open ones.
local TODO_KEYWORDS = { 'TODO NEXT PEND TEST WARN | DONE' }

-- The order the board's per-state subsections read in. Deliberately neither
-- the keyword sequence above nor alphabetical: the states asking for action
-- come first (TEST, NEXT, TODO), the parked one next (PEND), the problematic
-- one last (WARN). A keyword absent from this list -- one added to
-- TODO_KEYWORDS and forgotten here -- sorts after the listed ones, in keyword
-- sequence.
local BOARD_STATE_ORDER = { 'TEST', 'NEXT', 'TODO', 'PEND', 'WARN' }

-- The order the group view's (`2`) per-state sections read in: the states
-- asking for action first -- TEST, the entry waiting on validation, then
-- NEXT, the one being worked on -- the parked PEND and the problematic WARN
-- after them, and TODO last: the untouched rest is what the view is read
-- for, not what it opens on. Same escape hatch as BOARD_STATE_ORDER: a
-- keyword absent from the list sorts after the listed ones, in keyword
-- sequence.
local GROUP_STATE_ORDER = { 'TEST', 'NEXT', 'PEND', 'WARN', 'TODO' }

--- The per-state sections a state-split block groups by: one section per
--- open keyword, named with just the keyword, in `order`'s sequence (see
--- BOARD_STATE_ORDER / GROUP_STATE_ORDER above), plus the `someday` discard
--- every custom view keeps.
---@param order string[]
---@return table[]
local function state_sections(order)
  local rank = {}
  for i, kw in ipairs(order) do
    rank[kw] = i
  end
  local states = {}
  for i, kw in ipairs(vim.split(vim.split(TODO_KEYWORDS[1], '|')[1] or '', '%s+', { trimempty = true })) do
    states[#states + 1] = { kw = kw, rank = rank[kw] or math.huge, pos = i }
  end
  table.sort(states, function(a, b)
    if a.rank ~= b.rank then
      return a.rank < b.rank
    end
    return a.pos < b.pos
  end)
  local out = { { discard = { tag = 'someday' } } }
  for i, s in ipairs(states) do
    out[#out + 1] = { name = s.kw, todo = s.kw, order = i }
  end
  return out
end

-- The classification sections' state list, ordered by BOARD_STATE_ORDER (the
-- `°` view, which used to carry its own org-super-agenda `auto_todo`
-- ordering, is the board itself now). The board blocks below share the table
-- (the grouper copies it); the "In progress" block sets `super_groups =
-- false` and lists NEXT/TEST mixed across tags, so in the classification
-- sections those two keywords match nothing and their subsections are
-- dropped -- the derivation is kept whole so a new open keyword still lands
-- in one. helpers/org/agenda.lua only reads it -- and, for the blocks marked
-- `state_sections`, keeps the rule under the section's header rather than
-- between the subsections.
local BOARD_SECTIONS = state_sections(BOARD_STATE_ORDER)

-- The group view's state list (the `g` block below, key `2`): the open
-- entries of the cwd project's whole file, one section per keyword, in
-- GROUP_STATE_ORDER. Inside a section the entries are ordered by their
-- last-changed date -- the one helpers/org/changed.lua prints in the column,
-- newest first (`changed-down`) -- instead of by priority, so what the column
-- says is what the list is read in. The sections are drawn the default way
-- (a blank line before each header), not as a `state_sections` block: the
-- view is one flat block, with no section header to underline with a rule.
local GROUP_SECTIONS = state_sections(GROUP_STATE_ORDER)

-- The board's three classification sections (the `w` blocks below; the
-- "In progress" one above them is a plain keyword block and the Done one is
-- flat and ordered by completion date): the open entries carrying one
-- classification tag, split into the per-state subsections of
-- BOARD_SECTIONS and ordered by priority inside each -- A/B/C first, the
-- default urgency order settling the ties. No priority means the
-- unprioritized value, so those entries sort after C. helpers/org/agenda.lua
-- reads the two markers: `state_sections` keeps only the rule under the
-- section's own header, telling the subsections apart by a blank line, and
-- `hide_empty` drops the section -- its header included -- when it holds
-- nothing, so an empty one is not shown at all.
local function board_section(match, header)
  return {
    type = 'tags_todo',
    match = match,
    header = header,
    super_groups = BOARD_SECTIONS,
    state_sections = true,
    hide_empty = true,
    sorting = { 'priority-down', 'urgency-down', 'category-keep' },
  }
end

-- The `p` view below lists the entries carrying a priority cookie, so its
-- two blocks skip the ones that carry none. A `PRIORITY` match cannot tell
-- them apart: a cookie-less entry resolves to the file's default priority,
-- `B` (org-default-priority), in Emacs too -- `org-entry-get` answers "B"
-- there -- so `PRIORITY="B"/!` claimed every unprioritized open entry and
-- the old view filled its Priority B section with them. The cookie is what
-- the user set; `hl.priority` is nil without one (org.parser).
local function unprioritized(hl)
  return hl.priority == nil
end

-- org-agenda-cmp-user-defined for the `d` Done view below (`sorting =
-- { 'user-defined-down' }`): the entries ordered by the CLOSED planning
-- timestamp, i.e. most recently finished first. The stock strategies cannot
-- do it -- timestamp-* / ts-* / tsia-* read an active timestamp, or the first
-- inactive one from the section, and the planning line is not part of either
-- (org.parser keeps CLOSED in leading.planning, out of headline.timestamps).
-- The comparator orders ascending by minute (older first); user-defined-down
-- reverses it. An entry that was never logged (no CLOSED) has no date: its
-- rule cannot ride on the direction, since `user-defined-down` only swaps the
-- arguments, so such an entry leads the Done list rather than sinking under
-- the dated ones (helpers/org/changed.lua, whose own strategies sink it, is
-- where a direction-independent rule lives).
local function done_recency(a, b)
  local ha, hb = a.headline, b.headline
  local da = ha and ha.planning and ha.planning.closed
  local db = hb and hb.planning and hb.planning.closed
  if da == nil and db == nil then
    return false
  elseif da == nil then
    return 1
  elseif db == nil then
    return -1
  end
  local ma, mb = da:minutes(), db:minutes()
  if ma == mb then
    return false
  end
  return ma < mb and -1 or 1
end

return {
  'xheisenbugx/org.nvim',
  main = 'org',
  lazy = false, -- startup cost is small: heavy modules load on first use
  opts = {
    org_directory = '~/org',
    agenda_files = { '~/org/**/*.org' },
    default_notes_file = '~/org/refile.org',
    -- id: links resolve through the agenda files first, then through their
    -- archives (id.search_archives), then through `extra_files`. The boards
    -- roll closed tickets into ~/org/archive/<client>/<YYYY-MM>.org_archive
    -- (helpers/org/roll.lua) -- a file per client per month, which no static
    -- `#+ARCHIVE:` keyword can enumerate -- so the whole archive tree is added
    -- here by glob. This is what keeps a knowledge-base link to an archived
    -- ticket resolving years after the roll. The old
    -- ~/org/projects/*.org_archive are covered too.
    id = {
      extra_files = {
        '~/org/archive/**/*.org_archive',
        '~/org/projects/*.org_archive',
      },
    },
    -- An entry cannot be marked DONE while it still has an unfinished child
    -- (org's org-enforce-todo-dependencies; off in org.nvim's own defaults).
    -- Only DONE is guarded: the open keywords of this vault's set
    -- (TODO NEXT PEND TEST WARN) can be set on a parent freely, so a ticket
    -- handed back as TEST/WARN/PEND is never blocked. A refused change warns
    -- and opens the entry's tree, so the child that blocks it is on screen
    -- (helpers/org/reveal.lua); `force` (C-u C-u C-u <C-c><C-t>) and the
    -- :NOBLOCKING: property change the state anyway.
    enforce_todo_dependencies = true,
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
      -- Never ask before `dd` / <C-k> deletes an entry from the view (the
      -- default asks above a 1-line entry, org-agenda-confirm-kill). The
      -- kill mapping lives in mappings.agenda below.
      confirm_kill = false,
      -- Cross-project roll-ups: every other view (agenda_files, the TODO
      -- picker) reads one project, so the tags and priorities the ticket
      -- lines already carry are only visible here. Reached from the
      -- dispatcher menu or `:Org agenda <key>`, which give the whole set;
      -- the agenda buffer's 1 / 2 / 3 / 4 (helpers/org/agenda.lua) open
      -- them, 1 global, 2 the whole file of the cwd's project (the `g` list,
      -- its entries split per open keyword), and the rest
      -- narrowed to cwd's project. `°` (helpers/org/project.lua) opens
      -- the `w` board the same scoped way, so it is an alias for the `3`
      -- key. The keys avoid the built-in
      -- dispatcher ones (a t T m M s S n # / < > e * ?), so they add rows
      -- instead of replacing. Blocks are `tags_todo`
      -- (tags/property match, TODO entries only) -- the `/!` trailing the
      -- match is the TODO part of |org-match-syntax|, "not done", and the
      -- `-NEXT-TEST` after it excludes those keywords. `o` is every open
      -- TODO (`type = 'todo'`, org's `alltodo`); `w` is the board --
      -- the "In progress" block (every NEXT and TEST entry, any tag), then
      -- the classification sections -- bug tag, feat tag, chore tag, the
      -- untagged rest -- and DONE last, in that order, so a ticket moves
      -- between sections as it changes state (`DONE` is a `todo` block, not
      -- `tags_todo`, so the finished entries are listed, not filtered out).
      -- The classification sections are the `board_section` helper's, one
      -- subsection per remaining open keyword (TODO, PEND, WARN --
      -- BOARD_STATE_ORDER) with a blank line between -- the section's own
      -- header carries the only rule -- and ordered by priority
      -- inside each, so a ticket also moves between subsections as it
      -- changes state. A section holding nothing is not drawn -- the "In
      -- progress" and Done blocks included -- and the sections are told
      -- apart by a blank line, not a rule (a rule only under a section's
      -- header); `p` the open A/B priorities. A block's
      -- `header` labels the group; a composite command shows its blocks one
      -- after the other, in this order.
      custom_commands = {
        o = {
          description = 'All open TODOs',
          types = {
            { type = 'todo', header = 'All open TODOs' },
          },
        },
        -- Key `2`'s view: the `o` list of the cwd project's whole file --
        -- every headline of it, the projects a shared file hosts included --
        -- split into one section per open keyword (GROUP_SECTIONS,
        -- NEXT/PEND/WARN/TODO), each ordered by the entry's last-changed date
        -- rather than by category. What used to head these sections -- the
        -- top-level headline each entry sits under -- the entry lines carry
        -- themselves, as the category column (helpers/org/project.lua
        -- item_name labels a headline project's entries with its name).
        g = {
          description = 'All open TODOs of the file, by state',
          types = {
            {
              type = 'todo',
              header = 'All open TODOs',
              super_groups = GROUP_SECTIONS,
              hide_empty = true,
              sorting = { 'changed-down' },
            },
          },
        },
        w = {
          description = 'In progress, bugs, features, chores, untagged and done',
          types = {
            -- Every NEXT and TEST entry, whatever its classification tag, in
            -- one block at the top of the board: the states that ask for
            -- action, mixed across categories instead of split into the
            -- per-tag sections below. A plain `todo` keyword block --
            -- `match = 'NEXT|TEST'` is the keyword list render.lua reads --
            -- and `super_groups = false` keeps the extension from drawing
            -- the state subsections the sections below use, so the entries
            -- stay in one list. The sorting puts the keyword first
            -- (`todo-state-up`: NEXT before TEST, org's sequence) and then
            -- priority; no `category-keep`, so the categories interleave.
            {
              type = 'todo',
              match = 'NEXT|TEST',
              header = 'In progress',
              hide_empty = true,
              super_groups = false,
              sorting = { 'todo-state-up', 'priority-down', 'urgency-down' },
            },
            -- the classification sections: the open entries carrying one
            -- tag, minus the NEXT/TEST states the block above already
            -- listed (`/!-NEXT-TEST` -- not done, keyword not NEXT/TEST --
            -- so a ticket leaves its section as it enters progress and only
            -- the TODO/PEND/WARN rest stays). An untagged project whose
            -- every open entry is in progress keeps no section at all
            -- (`hide_empty`).
            board_section('bug/!-NEXT-TEST', 'Bugs, open'),
            board_section('feat/!-NEXT-TEST', 'Features, open'),
            board_section('chore/!-NEXT-TEST', 'Chores, open'),
            -- the open entries carrying no classification tag: the section
            -- new captures land in before they are sorted into
            -- bug / feature / chore
            board_section('-bug-feat-chore/!-NEXT-TEST', 'Untagged, open'),
            {
              type = 'todo',
              match = 'DONE',
              header = 'Done',
              -- shown only when it holds something, like the open sections
              hide_empty = true,
              -- a `─` rule above the header sets the finished entries apart
              -- from the open sections (helpers/org/agenda.lua insert_rule)
              rule_above = true,
              -- Flat: a done entry has nothing to schedule or prioritize, so
              -- it must not fall into the open-entry groups the other views
              -- share (a DONE entry keeping its DEADLINE would otherwise be
              -- claimed by "Due soon"). `false` opts out of the groups
              -- helpers/org/agenda.lua would give a block that sets none.
              super_groups = false,
              -- Most recently finished first: user-defined-down reverses
              -- done_recency above, which orders the entries by CLOSED
              -- ascending. Replaces the default todo sorting (urgency-down),
              -- which says nothing about a finished entry. The board
              -- (digit 3 / `°`), the dispatcher menu's `w` and `°`
              -- (helpers/org/project.lua) all deep-copy this block.
              sorting = { 'user-defined-down' },
            },
          },
        },
        p = {
          description = 'Open A/B priorities',
          types = {
            { type = 'tags_todo', match = 'PRIORITY="A"/!', header = 'Priority A, open', skip = unprioritized },
            { type = 'tags_todo', match = 'PRIORITY="B"/!', header = 'Priority B, open', skip = unprioritized },
          },
        },
      },
      -- org-agenda-cmp-user-defined: the comparator `user-defined-up` /
      -- `user-defined-down` call, defined once here (done_recency, at the top
      -- of this file) and used by the `w` board's Done section above. It
      -- compares the CLOSED planning timestamp, so nothing else in the config
      -- may use a user-defined strategy or it would sort by completion date
      -- too.
      cmp_user_defined = done_recency,
      -- The entry lists show the top level only: a TODO / tag block lists a
      -- matched top-level entry and skips its subtree
      -- (org-agenda-todo-list-sublevels / org-tags-match-list-sublevels
      -- off), so a sub-task never appears as a line of its own. In a TODO
      -- view helpers/org/tree.lua re-adds a listed entry's subheadlines --
      -- the sub-TODOs included -- nested under it, folded at level 1: a
      -- sub-task shows only when its entry is expanded. The date views
      -- (agenda_block) don't list entries this way and are untouched.
      todo_list_sublevels = false,
      tags_match_list_sublevels = false,
      -- Line prefix (org-agenda-prefix-format) for the entry lists. The stock
      -- `" %i %-12:c"` is kept, and the `todo` kind -- the board (digit 3 /
      -- `°`) and the global `o` (digit 1, and `2`'s whole-file group view)
      -- gains the entry's last-changed date before the keyword, the date
      -- the entry last moved: helpers/org/
      -- changed.lua takes the newest timestamp the entry carries (CLOSED, a
      -- note/capture header, an edited date) and reads it relative while
      -- recent ("today 15:53", "3d ago") and as "9 Oct" past a week.
      -- The same date is what the group view (`2`) sorts its sections by
      -- (`changed-down`, registered by that module's setup).
      -- `%?-13(...)` is the `%(lua expression)` element: an entry with no
      -- timestamp drops the field instead of leaving a gap. The other kinds
      -- (agenda, tags, search) keep their default formats -- a table here
      -- merges into the defaults.
      prefix_format = {
        todo = ' %i %-12:c %?-13(require("helpers.org.changed").label(hl))',
      },
      -- Emacs' org-agenda-show-outline-path: echo the outline path of the
      -- entry at point on every cursor move. Off here, because org.nvim
      -- echoes it as a message and Neovim answers any message wider than the
      -- window with the hit-enter prompt (`Press ENTER or type command to
      -- continue`), which then eats the next `j` / `k`. Launching an omp
      -- instance splits the tmux window, so every ticket line -- the long
      -- ones a project file is full of -- is wider than what nvim has left.
      -- The entry line already carries the category, and the `°` board
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
    -- `t` is spelled out in full. `%U` is the inactive timestamp with the
    -- time (%u is the date alone), so the created entry opens the body's
    -- chronological log with the same header shape as a note
    -- (helpers/org/notes.lua). `%?` sits on the headline, so a description
    -- typed below the title in the capture buffer lands *between* the title
    -- and the header; the template's `hook` (helpers/org/capture.lua) keeps
    -- the header back directly under the headline as the entry is typed --
    -- the description, and the cursor, below it -- and the store filter there
    -- finishes the same reorder (title, header, description) and indents the
    -- description like it, for a buffer that was not kept in order.
    --
    -- The tags a capture inherits are appended to its headline by the second
    -- store filter there (`capture_tags`): the destination headline's own and
    -- inherited tags, or its file's `#+FILETAGS:` -- so a `#+FILETAGS:
    -- allitude` file with a `PMS :pms:` headline captures `:allitude:pms:`,
    -- the same default tags the agenda shows through org tag inheritance.
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
          template = '* TODO %?\n  %U ' .. string.rep('-', notes.DASHES),
          -- Keep the buffer in title/header/description order while the
          -- entry is typed (lua/helpers/org/capture.lua `hook`).
          hook = capture.hook,
        },
      },
    },
    -- Same sequence as the old nvim-orgmode config (lua/plugins/org.lua at
    -- 630ef07^): TODO NEXT PEND TEST WARN | DONE. The project files use
    -- WARN/PEND/NEXT/TEST, which were plain text before.
    todo_keywords = TODO_KEYWORDS,
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
      -- Emphasis markers hidden: `*bold*` shows as bold, `/italic/` as
      -- italic, and the rest (`_`, `=`, `~`, `+`) likewise, the way the
      -- markdown plugin hides its own (`**`, `*`, `` ` ``, `~~`). The
      -- markdown markers are hidden by nvim-treesitter's `markdown_inline`
      -- query, which the org buffer gets too for the block bodies injected
      -- by queries/org/injections.scm; org's own markup is vim syntax
      -- (org.nvim's generated one), so it needs this option. `concealcursor`
      -- stays "nc" (plugins/markdown.lua's org override), so insert mode
      -- shows the markers raw, as the markdown plugin does on the cursor
      -- line.
      hide_emphasis_markers = true,
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
        -- org.nvim's own agenda/capture dispatchers claim <leader>oa and
        -- <leader>oc globally, and its setup runs after the mappings
        -- loader (init.lua), so they would shadow the direct actions
        -- lua/mappings.lua binds there. `false` is the documented way to
        -- drop a mapping (org.config.lhs_list -> no lhs); leaving the key
        -- out (nil) would keep the default <prefix>a / <prefix>c.
        agenda = false,
        capture = false,
        pick_project_todo = '<prefix>s',
      },
      agenda = {
        -- next/previous span. `J` / `K` are left to the global half-page
        -- scroll (lua/mappings.lua: J = <C-d>, K = <C-u>) so pagination
        -- works in the agenda and the TODO view -- both render into the
        -- same orgagenda buffer -- the same as in any other buffer. The
        -- span keys move to `)` / `(` (free here) with the plugin's `b`
        -- for earlier. `f` stays on the global `f = /` mapping
        -- (lua/mappings.lua) so search works in the agenda.
        later = ')',
        earlier = { 'b', '(' },
        -- A TODO view (helpers/org/tree.lua) shows an entry's sublevels --
        -- the plain subheadlines and the entry's own checkbox items
        -- included -- as a tree folded at level 1,
        -- and `<Tab>` there is fold-only: it cycles the node at point,
        -- org-style (folded -> children -> subtree -> folded), or, on a
        -- plain line, folds the group of the header there, which this key
        -- would otherwise shadow -- never org.nvim's `goto`, which opened
        -- the entry's source file in a split (`<S-CR>` / `o` / `<CR>` are
        -- the keys that leave the view). `<S-Tab>` cycles every node of the
        -- view, `l` unfolds the node at point one step (or the folded group
        -- header of an agenda view), and `c` captures a child of the entry
        -- at point (the longer `<leader>aC` is the same action). `r` on an
        -- entry refiles its subtree into another headline of the same view
        -- -- the entries on screen are the only targets -- and keeps
        -- org.nvim's `redo` on any other line (and in the day/week agenda):
        -- `gr` rebuilds from anywhere. `<CR>` on a checkbox line toggles
        -- that box in the entry's own file, the way `<CR>` on a checkbox
        -- item does in an org buffer (helpers/org/mappings.lua); on every
        -- other line it stays the entry scratch below. All buffer-local, set
        -- in helpers/org/tree.lua. The config-wide refile (`R`, <C-c><C-w>,
        -- refile.targets) is untouched.
        clock_goto = '<C-c><C-x><C-j>',
        capture = '<C-c>k',
        -- log mode keeps only its `v` spelling: `l` unfolds the node or
        -- group at point (helpers/org/tree.lua) and must not be shadowed by
        -- the default `l`.
        log_mode = 'vl',
        -- <leader>n adds a timestamped note under the entry at point
        -- (org-add-note); the default `z` stays
        add_note = { 'z', '<leader>n' },
        -- `D` toggles the entry's state between DONE and TODO (the action
        -- is registered by helpers/org/agenda.lua in the config function
        -- below) and leaves the cursor on the line it acted on, so a run of
        -- entries can be marked done without the cursor following each into
        -- the Done section. It takes the place of the default `D` (toggle
        -- the Emacs diary), unbound here.
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
        -- One-key tagging and priorities on the entry at point
        -- (helpers/org/tagging.lua, actions registered in
        -- helpers/org/agenda.lua): B/F/C toggle :bug:/:feat:/:chore:,
        -- <M-a>/<M-b>/<M-c> toggle the A/B/C priority. Takes the plain
        -- B / F / C defaults to make room: bulk_action loses its key
        -- (nothing else claimed it), follow_mode keeps `vf`, clock_report
        -- keeps `vR`. The priorities sit on <M-> because B and C are the
        -- tag keys.
        bulk_action = false,
        follow_mode = 'vf',
        clockreport_mode = 'vR',
        toggle_bug_tag = 'B',
        toggle_feat_tag = 'F',
        toggle_chore_tag = 'C',
        toggle_priority_a = '<M-a>',
        toggle_priority_b = '<M-b>',
        toggle_priority_c = '<M-c>',
        -- `c` captures a TODO as a child (subtree) of the entry at point
        -- (helpers/org/tree.lua binds it, alongside <leader>aC). It takes
        -- over the default `c` (org-agenda-calendar, the calendar buffer),
        -- unbound here.
        calendar = false,
        -- `|` quits like `q`, taking over the default `|` (remove the
        -- filter at point), unbound here
        quit = { 'q', '`' },
        filter_remove = false,
        -- `dd` deletes the entry's whole subtree in the source file, like
        -- the Emacs key <C-k> (kept): org-agenda-kill, the kill action in
        -- org.agenda.view, which removes `hl.line..hl.end_line` from the
        -- entry's own buffer. No confirmation, even for a multi-line
        -- subtree: `agenda.confirm_kill` is off above, so a `dd` deletes
        -- at once. It takes over neither `d` nor its <C-c><C-d> --
        -- agenda's deadline: with `dd` bound, a lone `d` waits a moment
        -- for the second key and still sets the deadline.
        kill = { '<C-k>', 'dd' },
        -- `a` archives the entry at point at once. Default is archive with
        -- confirmation (org-agenda-archive-default-with-confirmation, which
        -- asks "Archive this subtree or entry?"); here `a` takes over the
        -- plain org-agenda-archive-default action, which does not ask. The
        -- Emacs key <C-c><C-x><C-a> keeps working, now also unconfirmed.
        archive_default_confirm = false,
        archive_default = { '<C-c><C-x><C-a>', 'a' },
        -- `^` is the global org capture key (lua/mappings.lua). The default
        -- agenda `^` (filter to the top headline) would shadow it in the
        -- agenda and in the TODO view, which renders into the same buffer.
        filter_top_headline = false,
        -- <CR> opens the entry at point by itself: only its own lines
        -- (headline through the end of its subtree) in an editable scratch
        -- buffer that takes over the view's window, `q` back
        -- (helpers/org/agenda.lua setup_entry_scratch). The buffer wraps by
        -- default and `:w` splices it back into its file in place of the
        -- entry; the whole file stays out of the way of a long project file.
        -- In a TODO view a checkbox line keeps <CR> for itself -- it toggles
        -- that box in the entry's file (helpers/org/tree.lua); every other
        -- line opens the entry scratch.
        -- The old <CR> behaviour (switch_to: the entry opened in its file,
        -- the view left behind) moves here to <S-CR>, which opens the `show`
        -- default to make room. `o` reaches the same action: the view
        -- already owns the window, so the default `o`
        -- (delete_other_windows, unbound here) does nothing useful.
        -- <Space> is left to the leader (init.lua): a view mapping on it
        -- would wait 'timeoutlen' on every leader sequence, and a lone press
        -- would leave the view -- switching to the entry's file, or opening
        -- the event-detail scratch on a calendar line
        -- (helpers/org/ics.lua) -- instead of doing nothing.
        entry_scratch = '<CR>',
        -- `L` opens the same entry scratch beside the view instead of in it
        -- (helpers/org/agenda.lua setup_entry_preview): a preview window on
        -- the right holding the entry at the cursor, reloaded as the cursor
        -- moves to another entry and when the entry it already holds changes
        -- (a note added with `z` under it, say). `L` again, `q` in the pane,
        -- or leaving the view closes it. The default `L` (recenter: the entry
        -- shown in its file, in another window) is unbound to give it the key
        -- -- two actions on one lhs would leave the winner to the mapping
        -- table's iteration order.
        recenter = false,
        entry_preview = 'L',
        switch_to = { '<S-CR>', 'o' },
        delete_other_windows = false,
        show = false,
        -- `?` opens the full keymap help, the float `g?` already opens, in
        -- the agenda and in the TODO view (both render into the same
        -- orgagenda buffer). It takes over the default `?`
        -- (org-agenda-show-the-flagging-note, the mobile-flag note -- unused
        -- here, where an unflagged entry only warned "No note"), unbound.
        help = { 'g?', '?' },
        show_flagging_note = false,
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
        -- `t` adds/edits the tags of the entry at point (org-set-tags)
        -- moves to <prefix>T: <prefix>t is the global project TODO view
        -- (lua/mappings.lua) and a buffer-local key here would shadow it
        -- in every org file. <prefix>T is not bound to any other action,
        -- but org.nvim's table keys hang off it (<prefix>Tc, <prefix>T-,
        -- <prefix>Tf, ...): those still win once their next key is typed,
        -- `T` alone just waits out 'timeoutlen' first.
        set_tags = '<prefix>T',
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
        -- No pick_project_todo key here (false): the picker was on <C-p>,
        -- but <C-p> must stay the global fff file finder in org files too,
        -- as it is everywhere else. The picker keeps its global <leader>os
        -- (helpers/org_todo.pick), the only key the agenda and the TODO
        -- view have for it, and a double-tap of the leader opens the roam
        -- node finder instead (helpers/org/mappings.lua).
        pick_project_todo = false,
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
        -- <prefix>$ alone still archives just the subtree at point. The
        -- action is overridden in config() (helpers/org/archive.lua →
        -- helpers/org/roll.lua): it sweeps every workstream of the board at
        -- once, into ~/org/archive/<client>/<YYYY-MM>.org_archive, without
        -- org.nvim's per-entry "Move subtree to archive?" confirmation.
        archive_all_done = '<prefix>D',
        -- the same sweep with a week's grace: only what closed more than
        -- seven days ago, so a mis-tapped DONE is not carried off at once
        -- (helpers/org/roll.lua, registered in config()).
        archive_all_old = '<prefix>A',
        -- the inverse: the archived entry at point goes back into its board,
        -- under the parent its drawer's :ARCHIVE_OLPATH: records. org.nvim has
        -- no other un-archive (helpers/org/roll.lua, registered in config()).
        unarchive = '<prefix>U',
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
      -- lsp = {},
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
          -- the catch-all. Nameless (`auto_map` returning ''): the extension
          -- draws no header for an empty section name, so the entries the
          -- named groups above leave simply follow the last one -- a day's
          -- deadline and scheduled reminders read as one list, not one
          -- "Category: <project>" split per category. The custom views
          -- (helpers/org/agenda.lua view_groups) swap it for a title map --
          -- the project file's level-1 headline, "Nvim" not "Category:
          -- nvim" -- and, scoped to one project, back for a nameless one:
          -- the category is the same under all of a board's sections and
          -- the block header ("Nvim - Bugs, open") already names it once.
          {
            auto_map = function()
              return ''
            end,
            order = 9,
          },
        },
      },
      -- org-roam: the knowledge base under ~/org/roam, no longer the
      -- playground sandbox (kept as reference, out of the graph by the
      -- exclude below). index.org says what lives where, the tags and the
      -- properties; every `.org` below `directory` is indexed; the keys are
      -- under <leader>om and the index under
      -- stdpath("data")/org/roam-index.json. The backlinks window
      -- (`<leader>oml`, and `<leader>e` in a roam file) opens on the left
      -- rather than the default right.
      roam = {
        directory = '~/org/roam',
        exclude = { 'data/', '^playground/' },
        buffer = { position = 'left' },
        -- Where a capture that needs a *new* node file lands. Under the
        -- mirror (index.org) new files are rare: documentation/ is seeded
        -- from ~/org/projects/, and a finding is a level-3 headline inside
        -- one of those files, made by capturing *into* an existing node. So
        -- the only new files are a topic with no workstream home and a
        -- person -- and `d` (the keyless default) is a topic, so nothing is
        -- ever scattered at the roam root, which is where the plugin's own
        -- timestamped default target would put it. Slugs, never timestamps:
        -- the title is the node's identity, and `${slug}` keeps the file name
        -- greppable from a link.
        capture_templates = {
          d = {
            description = 'topic',
            type = 'plain',
            template = '%?',
            target = 'topics/${slug}.org',
            head = '#+title: ${title}\n#+filetags: :kb_entity:\n',
          },
          k = {
            description = 'person',
            type = 'plain',
            template = '%?',
            target = 'people/${slug}.org',
            head = '#+title: ${title}\n#+filetags: :kb_entity:\n',
          },
        },
        -- `<leader>omx` (extract): a macro topic that outgrew its file becomes
        -- a topic node, the way a ticket outgrows the board.
        extract_new_file_path = 'topics/${slug}.org',
      },
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
    -- `<prefix>D` rolls every finished ticket off the board: the action is
    -- replaced so it sweeps without org.nvim's per-entry confirmation, and so
    -- it goes to this month's archive file rather than a `<file>.org_archive`
    -- that grows forever (helpers/org/archive.lua → helpers/org/roll.lua).
    require('org.actions').list.archive_all_done = {
      'helpers.org.archive',
      'archive_all_done',
      desc = 'Roll finished tickets into this month’s archive',
    }
    -- `<prefix>A` is that sweep with a week's grace (only what closed over
    -- seven days ago), `<prefix>U` its inverse: the entry at point goes back
    -- into the board the drawer's :ARCHIVE_FILE: names, under the headline
    -- its :ARCHIVE_OLPATH: names (helpers/org/roll.lua).
    require('org.actions').list.archive_all_old = {
      'helpers.org.roll',
      'roll_aged',
      desc = 'Roll tickets closed over a week ago',
    }
    require('org.actions').list.unarchive = {
      'helpers.org.roll',
      'unarchive',
      desc = 'Un-archive the entry at point into its board',
    }
    require('org').setup(opts)

    -- Order matters where noted in the helpers: the FileType mappings must
    -- land after org.nvim attaches its own buffer mappings. setup() here is
    -- cheap: the helpers plug into org modules the plugin loads on first
    -- use through org.lazy.on_load (or plain autocmds), so no part of
    -- org.nvim is required at startup.
    --
    -- cookies first of all: its OrgCaptureAfterFinalize listener (reopen a
    -- finished parent, refresh the target's statistics cookies) must run
    -- before the agenda's own listener on that event, so the view agenda
    -- re-renders there shows both.
    require('helpers.org.cookies').setup()
    require('helpers.org.agenda').setup()
    require('helpers.org.tree').setup()
    require('helpers.org.reveal').setup()
    require('helpers.org.callouts').setup()
    require('helpers.org.decorations').setup()
    -- the group view's `changed-down` sorting strategy: it reads the same
    -- last-changed date the column shows (helpers/org/changed.lua), so it
    -- goes in with the view's own pieces
    require('helpers.org.changed').setup()
    require('helpers.org.notes').setup()
    capture.setup()
    require('helpers.org.mappings').setup()
    require('helpers.org.folding').setup()
    require('helpers.org.refile').setup()
    require('helpers.org.ics').setup()
    require('helpers.org.ai').setup()
    require('helpers.org.retro').setup()
    require('helpers.org.kb').setup()
    require('helpers.org.actions').setup()
  end,
}
