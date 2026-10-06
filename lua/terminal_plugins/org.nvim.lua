-- Lives in terminal_plugins/ (imported in every launch) so org works in the
-- tmux `nvim +terminal` session that `alt+o` / t-script.sh opens, not only in
-- the full config: init.lua skips the whole plugins/ import when +terminal.
--
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

-- Capture-task destination. The Task template asks where the entry goes
-- before the note is typed, and stores it there directly, instead of
-- dropping it in refile.org and refiling it again. The list is flat: the
-- level-1 headlines of the project files (the projects), no stepping
-- through the outline path, no whole-file entries. `target` and `headline`
-- of the template read the pick memoized here, so it runs once per
-- capture. Cancelling the picker aborts the capture (utils.abort), so
-- nothing lands in the default notes file.
local task_dest
local function pick_task_dest()
  local utils = require 'org.utils'
  task_dest = nil
  local targets = require('org.refile').targets {
    targets = { { files = '~/org/projects/*.org', max_level = 1 } },
    bufnr = vim.api.nvim_get_current_buf(),
  }
  local headlines = {}
  for _, t in ipairs(targets) do
    -- whole-file targets carry no line number; keep headlines only
    if t.lnum then
      headlines[#headlines + 1] = t
    end
  end
  if #headlines == 0 then
    utils.warn 'capture: no level-1 headline in ~/org/projects/*.org'
    return nil
  end
  local choice = utils.select(headlines, {
    prompt = 'Task to',
    kind = 'org_capture_target',
    format_item = function(t)
      return string.format('%s  (%s)', t.olp[#t.olp], vim.fn.fnamemodify(t.filename, ':t'))
    end,
  })
  if choice then
    task_dest = { file = choice.filename, title = choice.olp[#choice.olp] }
  end
  return task_dest
end

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
    -- come from pick_task_dest above: the picker asks for the level-1
    -- project headline the task belongs to, and the entry is stored under
    -- it right away. A configured `templates` table replaces the defaults
    -- rather than merging into them, so `t` is spelled out in full.
    capture = {
      templates = {
        t = {
          description = 'Task',
          type = 'entry',
          target = function()
            pick_task_dest()
            if not task_dest then
              require('org.utils').abort()
            end
            return task_dest.file
          end,
          headline = function()
            return task_dest and task_dest.title
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
      agenda = {
        -- next/previous span; J/K too. `f` is left to the global
        -- `f = /` mapping (lua/mappings.lua) so search works in the agenda
        later = 'J',
        earlier = { 'b', 'K' },
        clock_goto = '<C-c><C-x><C-j>',
        capture = '<C-c>k',
        -- `D` toggles the entry's state between DONE and TODO (the action
        -- is registered in the config function below). It takes the place
        -- of the default `D` (toggle the Emacs diary), unbound here.
        toggle_done = 'D',
        toggle_diary = false,
      },
      org = {
        -- <CR> on a checkbox item toggles it, elsewhere cycles visibility
        -- (set up in the config function); <Tab> keeps cycling
        cycle = '<Tab>',
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
      kanban = {},
      -- lsp = {},
      -- cli = {},
      -- calendars described at the top of this file
      ics = { calendars = ics_calendars() },
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
  -- copies the event into an org file; :IcsPeek shows it in a read-only
  -- scratch buffer instead, taking over the agenda window (q / <C-^> back).
  config = function(_, opts)
    require('org').setup(opts)

    -- `D` in the agenda toggles an entry between DONE and TODO: a done
    -- entry goes back to TODO, anything else (open, or no keyword at all)
    -- becomes DONE. change_state runs the full org semantics (CLOSED
    -- timestamp, state logging, blockers, repeaters). The agenda mapping
    -- table only addresses actions by name, so the action is added to the
    -- agenda action table (org.agenda.view.actions); mappings.agenda
    -- above points `D` at it.
    local view = require 'org.agenda.view'
    view.actions.toggle_done = view.on_item(function(target)
      local bufnr, file, hl = require('org.edit').resolve_headline(target)
      if not bufnr then
        return
      end
      local done = file.settings.todo:is_done(hl.todo)
      return require('org.todo').change_state({ bufnr = bufnr, lnum = hl.line }, done and 'TODO' or 'DONE')
    end, 'lines')

    -- Checkbox rendering like the markdown config: `- [ ] text` shows as
    -- `- <icon> text`, the icon standing in for the box (`ui.checkboxes`
    -- above holds the glyphs). The stock renderer overlays the icon over
    -- `[ ]` and, for icons narrower than the three columns of the box,
    -- wraps it in literal brackets (`-[]`), which is what looked broken.
    -- The mark the renderer computes is rewritten here into a conceal of
    -- the three box columns with the icon character, so the line renders
    -- exactly as the markdown plugin's.
    local decorations = require 'org.ui.decorations'
    local compute = decorations.compute
    decorations.compute = function(bufnr, first, last, ui)
      local rows = compute(bufnr, first, last, ui)
      if not ui or type(ui.checkboxes) ~= 'table' then
        return rows
      end
      for _, marks in pairs(rows) do
        for _, m in ipairs(marks) do
          local virt_text = m[2].virt_text
          local group = virt_text and virt_text[1] and virt_text[1][2]
          local i = group == 'OrgCheckbox' and 1 or group == 'OrgCheckboxPartial' and 2 or group == 'OrgCheckboxChecked' and 3
          if i then
            -- the box `[ ]` is three bytes; conceal replaces all three with
            -- the icon (a single character)
            m[2] = {
              end_col = m[1] + 3,
              conceal = vim.fn.strcharpart(ui.checkboxes[i], 0, 1),
              hl_group = group,
            }
          end
        end
      end
      return rows
    end

    -- <CR> like the markdown config's smart action (obsidian
    -- util.toggle_checkbox), and insert-mode <CR> continuing lists like
    -- bullets.vim. Registered on FileType org so it lands after org.nvim
    -- attaches its own buffer mappings.
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'org',
      callback = function(args)
        local buf = args.buf

        local function get_line(lnum)
          return vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
        end

        local function set_line(lnum, text)
          vim.api.nvim_buf_set_lines(buf, lnum - 1, lnum, false, { text })
        end

        -- Inside a #+begin_... / #+end_... block: the nearest marker above
        -- decides (org blocks do not nest).
        local function in_block(lnum)
          for i = lnum - 1, 1, -1 do
            local line = get_line(i)
            if line:match '^%s*#%+[Bb][Ee][Gg][Ii][Nn]_' then
              return true
            elseif line:match '^%s*#%+[Ee][Nn][Dd]_' then
              return false
            end
          end
          return false
        end

        -- Normal-mode <CR>, like obsidian's smart action: cycle a headline
        -- (fold), toggle a checkbox, or turn the line into a checkbox -- a
        -- plain list item keeps its text, any other line is prefixed. The
        -- lines that are not "normal" org lines (headlines, tables,
        -- keywords/comments, drawers, blocks) keep the old fold behaviour.
        vim.keymap.set('n', '<CR>', function()
          local lnum = vim.api.nvim_win_get_cursor(0)[1]
          local line = get_line(lnum)
          local lists = require 'org.lists'
          local item = lists.item_at(buf, lnum)
          if item and item.checkbox then
            lists.toggle_checkbox()
            return
          end
          local indent = line:match '^([ \t]*)'
          local rest = line:sub(#indent + 1)
          -- a list item (checkboxless or ordered) becomes `- [ ] ` in
          -- place; only a `-+*` bullet keeps its leading whitespace
          local bullet_text = rest:match '^[-+*] (.*)$'
          if item then
            set_line(lnum, bullet_text and (indent .. '- [ ] ' .. bullet_text) or (indent .. '- [ ] ' .. rest))
            return
          end
          if line:match '^%*+ ' or line:match '^[ \t]*[|#:]' or line:match '^[ \t]*$' or in_block(lnum) then
            require('org.fold').cycle()
            return
          end
          if bullet_text then
            set_line(lnum, indent .. '- [ ] ' .. bullet_text)
            return
          end
          set_line(lnum, indent .. '- [ ] ' .. rest)
        end, { buffer = buf, desc = 'org: toggle / make checkbox, cycle visibility' })

        -- Insert-mode <CR> after bullets.vim: on a list item at the end of
        -- the line, continue the list with the same bullet (a checkbox item
        -- continues as `- [ ] `), an empty item is emptied instead, and a
        -- line ending in `:` indents the new item one level. Anywhere else
        -- a plain newline.
        vim.keymap.set('i', '<CR>', function()
          local lnum = vim.api.nvim_win_get_cursor(0)[1]
          local line = get_line(lnum)
          local item = require('org.lists').item_at(buf, lnum)
          if not item or vim.fn.col '.' ~= #line + 1 then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'n', false)
            return
          end
          if item.text == '' then
            set_line(lnum, '')
            vim.api.nvim_win_set_cursor(0, { lnum, 0 })
            return
          end
          local body = item.bullet .. ' '
          if item.checkbox then
            body = body .. '[ ] '
          end
          local indent = item.indent
          if line:sub(-1) == ':' then
            indent = indent + vim.fn.shiftwidth()
          end
          local new_line = string.rep(' ', indent) .. body
          vim.api.nvim_buf_set_lines(buf, lnum, lnum, false, { new_line })
          vim.api.nvim_win_set_cursor(0, { lnum + 1, #new_line })
        end, { buffer = buf, desc = 'org: continue list (like bullets.vim)' })

        -- dd on a headline deletes the whole subtree, like `dar`
        -- (org.structure's around-subtree range is hl.line..hl.end_line).
        -- Anywhere else, and on a childless headline, plain dd.
        vim.keymap.set('n', 'dd', function()
          local file = require('org.files').get_buffer(args.buf)
          local hl = file:headline_on(vim.api.nvim_win_get_cursor(0)[1])
          if hl then
            local last = hl.end_line
            for _ = 2, math.max(vim.v.count, 1) do
              local nxt
              for _, h in ipairs(file.headlines) do
                if h.line > last then
                  nxt = h
                  break
                end
              end
              if not nxt then
                break
              end
              last = nxt.end_line
            end
            if last > hl.line then
              vim.cmd(string.format('%d,%ddelete', hl.line, last))
              return
            end
          end
          vim.cmd 'normal! dd'
        end, { buffer = args.buf, desc = 'org: delete subtree (on a headline) / line' })
      end,
    })

    -- nvim-origami (plugins/origami.lua) loads at VeryLazy and sets a global
    -- foldmethod=expr + treesitter foldexpr. When an org buffer is already
    -- open at startup, that lands after org's window-local fold setup and
    -- flattens the #+STARTUP visibility (the org treesitter parser is not
    -- installed, so its foldexpr finds no folds). Re-assert org folding for
    -- org windows once origami has loaded: setup_buffer restores the fold
    -- options, set_startup_visibility reopens/closes to the STARTUP mode.
    vim.api.nvim_create_autocmd('User', {
      pattern = 'VeryLazy',
      callback = function()
        local fold = require 'org.fold'
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'org' then
            fold.setup_buffer(buf)
            for _, win in ipairs(vim.fn.win_findbuf(buf)) do
              vim.api.nvim_win_call(win, function()
                fold.set_startup_visibility()
              end)
            end
          end
        end
      end,
    })

    -- Launching the agenda from a terminal window (the `nvim +terminal`
    -- session) should take that window over, not split below the terminal.
    -- org.agenda.open reads agenda.window in show_buffer() while it runs, so
    -- swap in "current" for the call when the buffer is a terminal.
    local agenda = require 'org.agenda'
    local agenda_open = agenda.open
    agenda.open = function(spec, opts)
      if vim.bo.buftype == 'terminal' then
        local config = require 'org.config'
        local saved = config.opts.agenda.window
        config.opts.agenda.window = 'current'
        local ok, err = pcall(agenda_open, spec, opts)
        config.opts.agenda.window = saved
        if not ok then
          error(err)
        end
        -- The window held a terminal buffer; its autocommands
        -- (autocommands.lua: TermOpen / FocusGained / BufEnter term://*)
        -- call startinsert, and that lands in the agenda buffer right
        -- after it is set (logged: FileType orgagenda, then
        -- InsertEnter buftype=nofile name=agenda). Exit insert/terminal
        -- mode now, and once more for the insert that follows.
        local function normal_mode()
          local mode = vim.api.nvim_get_mode().mode
          if mode == 't' then
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, false, true), 'n', false)
          elseif mode:sub(1, 1) == 'i' then
            pcall(vim.cmd, 'stopinsert')
          end
        end
        normal_mode()
        local guard = vim.api.nvim_create_autocmd('InsertEnter', {
          callback = function()
            -- stopinsert during InsertEnter does not take; leave after
            vim.defer_fn(normal_mode, 0)
          end,
        })
        vim.defer_fn(function()
          pcall(vim.api.nvim_del_autocmd, guard)
        end, 2000)
        return
      end
      return agenda_open(spec, opts)
    end

    -- Capture-refile (org-capture-refile, <prefix>r in the capture buffer)
    -- stores the entry in the template's target (default_notes_file,
    -- refile.org) and then refiles it to the chosen target. org.nvim saves
    -- the refile destination but not the store buffer the move emptied
    -- (refile.lua saves the source only with `opts.save`, which the capture
    -- path does not pass), so the block stayed in refile.org on disk. Save
    -- that buffer once the refile succeeded.
    local capture = require 'org.capture'
    local capture_refile = capture.refile
    capture.refile = function(buf)
      local sources = {}
      local id = vim.api.nvim_create_autocmd('User', {
        pattern = 'OrgRefile',
        callback = function(args)
          local src = args.data.source_bufnr
          if src and src ~= buf and vim.api.nvim_buf_is_valid(src) then
            sources[src] = true
          end
        end,
      })
      local ok, dbuf, dline = pcall(capture_refile, buf)
      pcall(vim.api.nvim_del_autocmd, id)
      if not ok then
        error(dbuf)
      end
      for src in pairs(sources) do
        if vim.bo[src].modified then
          require('org.utils').save_buffer_or_warn(src)
        end
      end
      return dbuf, dline
    end

    -- Statistics cookies are bookkeeping, not user edits. A normal write
    -- would add its own undo step, so `u` after deleting an item undid the
    -- counter refresh instead of the deletion, and the refresh autocmds put
    -- it right back (a loop). `:undojoin` folds the write into the change
    -- that triggered it, so `u` undoes that change together with its counter
    -- update and no separate step appears. (Do NOT use undolevels = -1
    -- here: changing 'undolevels' clears the undo history.)
    local function joined(fn)
      return function(bufnr, ...)
        pcall(vim.cmd, 'silent! undojoin')
        return fn(bufnr, ...)
      end
    end
    local lists = require 'org.lists'
    lists.update_statistics_for = joined(lists.update_statistics_for)
    lists.update_statistics = joined(lists.update_statistics)
    lists.update_all_statistics = joined(lists.update_all_statistics)

    -- Automatic statistics cookies. Emacs and org.nvim only keep a `[/]` /
    -- `[x/y]` cookie up to date if it is already there (org.lists
    -- update_section rewrites only lines with a cookie); nothing inserts
    -- one. Here a `[/]` is added to every headline whose child entries have
    -- TODO keywords, or whose own section has checkboxes, and org.nvim then
    -- maintains the numbers. Runs when a file is parsed, on TODO state
    -- changes and shortly after edits (debounced).
    local updating = false
    local function ensure_cookies(bufnr)
      if updating or not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= 'org' then
        return
      end
      updating = true
      -- Freshly loaded buffer: nothing to merge into, and the history is
      -- empty, so write with undo disabled -- opening a file must not add an
      -- undo step. Later passes merge into the change that triggered them via
      -- `:undojoin` (see `joined`); they must NOT touch 'undolevels', which
      -- would discard the user's undo steps.
      local fresh = vim.fn.undotree().seq_cur == 0
      local saved_ul
      if fresh then
        saved_ul = vim.bo[bufnr].undolevels
        vim.bo[bufnr].undolevels = -1
      else
        pcall(vim.cmd, 'silent! undojoin')
      end
      local ok, err = pcall(function()
        local files = require 'org.files'
        local lists = require 'org.lists'
        local parser = require 'org.parser'
        local edit = require 'org.edit'
        local file = files.get_buffer(bufnr)
        local last = vim.api.nvim_buf_line_count(bufnr)
        for _, hl in ipairs(file.headlines) do
          if hl.line <= last and hl.raw:find '%[%d*[/%%]%d*%]' then
            -- an existing (possibly bare `[/]`) cookie: fill it in
            lists.update_statistics_for(bufnr, hl.line)
          elseif hl.line <= last then
            -- only parse the section when it could hold a checkbox
            local maybe_box = false
            for i = hl.line + 1, math.min(hl.body_end, last) do
              if file.lines[i]:find '[%[%]]' then
                maybe_box = true
                break
              end
            end
            local has_box = false
            if maybe_box then
              for _, l in ipairs(lists.parse_region(file.lines, hl.line + 1, hl.body_end)) do
                for _, it in ipairs(l.items) do
                  if it.checkbox then
                    has_box = true
                  end
                end
              end
            end
            local want = has_box or select(2, lists.todo_counts(file, hl)) > 0
            if want then
              local p = parser.parse_headline_line(hl.raw, file.settings.todo)
              if p then
                edit.update_headline(bufnr, hl.line, { title = (p.title or '') .. ' [/]' })
                lists.update_statistics_for(bufnr, hl.line)
                file = files.get_buffer(bufnr)
              end
            end
          end
        end
      end)
      if saved_ul then
        vim.bo[bufnr].undolevels = saved_ul
      end
      updating = false
      if not ok then
        require('org.utils').warn('statistics cookies: ' .. tostring(err))
      end
    end

    vim.api.nvim_create_user_command('OrgEnsureCookies', function()
      ensure_cookies(vim.api.nvim_get_current_buf())
    end, { desc = 'Add missing TODO/checkbox statistics cookies' })

    local queued = {}
    local function schedule_cookies(bufnr)
      if updating or queued[bufnr] then
        return
      end
      queued[bufnr] = true
      vim.defer_fn(function()
        queued[bufnr] = nil
        ensure_cookies(bufnr)
      end, 300)
    end
    vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
      callback = function(args)
        if vim.bo[args.buf].filetype == 'org' then
          schedule_cookies(args.buf)
        end
      end,
    })

    local api = require 'org.api'
    api.on('OrgFileLoaded', function(data)
      -- only buffers on screen: a hidden buffer loaded as a refile/capture
      -- target (e.g. refile.org while a capture is stored and refiled out
      -- again) would get a cookie for a state that no longer holds
      if data.bufnr and vim.fn.bufwinid(data.bufnr) ~= -1 then
        vim.schedule(function()
          ensure_cookies(data.bufnr)
        end)
      end
    end)
    api.on('OrgTodoStateChange', function(data)
      if data.bufnr then
        ensure_cookies(data.bufnr)
      end
    end)

    -- Most calendars (Google, Outlook) send the description as HTML. Pipe
    -- it through lynx so the scratch shows text/tables, not markup; keep
    -- the reference list, it carries the links. Falls back to a crude tag
    -- strip when lynx is missing.
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

    -- Only reached from an agenda buffer, so the scratch takes over the
    -- agenda's window; `q` goes back to the (hidden, bufhidden=hide) agenda.
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

    vim.api.nvim_create_user_command('IcsPeek', function()
      local view = require 'org.agenda.view'
      if not peek(vim.bo.filetype == 'orgagenda' and view.item_at_cursor() or nil) then
        vim.notify('ics: no calendar event on this line', vim.log.levels.WARN)
      end
    end, { desc = 'iCalendar event details of the agenda entry at the cursor' })

    -- <CR> (agenda.switch_to) on a calendar line opens the scratch instead
    -- of failing with "Command not allowed in this line"; on anything else
    -- it keeps its usual meaning.
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
  end,
}
