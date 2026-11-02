-- Buffer-local org mappings for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): normal-mode <CR> like the markdown
-- config's smart action (obsidian util.toggle_checkbox) -- except in a
-- capture buffer, where it opens a new line to type on, and saving that
-- buffer (`:w`) is what stores the entry and starts OMP on it --, plus
-- following
-- the link under the cursor, insert-mode <CR> continuing lists like
-- bullets.vim, dd deleting a whole subtree, the
-- one-key tag/priority toggles (helpers/org/tagging.lua), the roam capture
-- on <C-c><C-n> (helpers/org/capture.lua `roam`), and the
-- insert-mode capture keys (org.nvim binds those in normal mode only).
-- Registered on FileType org so they land after org.nvim attaches its own
-- buffer mappings.
local M = {}

--- Whether `bufnr` is a file of the roam extension (under its directory).
---@param bufnr integer
---@return boolean
local function is_roam(bufnr)
  local ok, db = pcall(require, 'org.extensions.roam.db')
  if not ok then
    return false
  end
  local ok_file, roam = pcall(db.is_roam_file, vim.api.nvim_buf_get_name(bufnr))
  return ok_file and roam or false
end

function M.setup()
  -- A capture buffer was saved: the finalize that follows is a launch, not
  -- just a store (the capture branch below marks it).
  local write_launch = false

  -- org.capture announces every stored capture -- `OrgCaptureAfterFinalize`,
  -- with the buffer and line the entry landed on -- whatever finished it: the
  -- capture key, `<leader>ai`, or a write. Only the write asks for a run (the
  -- BufWriteCmd in the capture branch marks it), so the mark decides; it is
  -- cleared here and in the mark's own scheduled reset, whichever comes
  -- first, so one saved capture starts one launch.
  vim.api.nvim_create_autocmd('User', {
    pattern = 'OrgCaptureAfterFinalize',
    callback = function(args)
      if not write_launch then
        return
      end
      write_launch = false
      local data = args.data or {}
      if not (data.bufnr and data.line) then
        return
      end
      -- out of the write's own autocmd run: the launch writes the ticket's
      -- drawer, saves the file and makes the run's checkpoint commit
      vim.schedule(function()
        require('helpers.org.ai').launch_at(data.bufnr, data.line)
      end)
    end,
    desc = 'org: start OMP on a capture stored by a write',
  })
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

      -- Normal-mode <CR>, like obsidian's smart action: follow the link
      -- under the cursor, else cycle a headline (fold), toggle a checkbox,
      -- or turn the line into a checkbox -- a plain list item keeps its
      -- text, any other line is prefixed. The lines that are not "normal"
      -- org lines (headlines, tables, keywords/comments, drawers, blocks)
      -- keep the old fold behaviour.
      vim.keymap.set('n', '<CR>', function()
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        local line = get_line(lnum)
        -- A link under the cursor wins, wherever it sits (headline, list
        -- item, plain line): follow it like the default open_at_point.
        local links = require 'org.links'
        if links.link_at_cursor() then
          links.open_at_point()
          return
        end
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
      end, { buffer = buf, desc = 'org: follow link / toggle / make checkbox, cycle visibility' })

      -- Visual-mode <CR>: insert a link to a roam node, the same action as
      -- <leader>omi (org-roam-node-insert). The selection is the node's
      -- default title and the inserted link's description, and is replaced
      -- by the link; a title with no existing node runs the roam capture.
      vim.keymap.set('x', '<CR>', function()
        require('org').action 'roam_node_insert'
      end, { buffer = buf, desc = 'org: roam node insert (<leader>omi)' })

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

      -- <C-c><C-n> writes into the knowledge base (helpers/org/capture.lua
      -- `roam`): a fuzzy finder picks the destination over the base's files
      -- and every headline in them -- level 2 and deeper included, whether
      -- or not the headline carries an `:ID:` -- and the entry lands there
      -- as a plain headline, never a ticket, with the link back to where it
      -- was written from. On a Visual selection the selection goes in as a
      -- `#+begin_src` block of its language, so an excerpt arrives with the
      -- note that explains it. Inside a capture buffer the same chord is the
      -- other half (`roam_refile`): the entry the capture holds is stored
      -- and refiled into the node picked there, its TODO keyword taken off
      -- on the way. Nothing starts an omp run on the stored note -- neither
      -- path writes the capture buffer (the capture branch below arms the
      -- launch for a write, and only for the Task template).
      vim.keymap.set({ 'n', 'x' }, '<C-c><C-n>', function()
        require('helpers.org.capture').roam()
      end, { buffer = buf, desc = 'org: capture into a roam node' })

      -- Capture buffers: the capture's own keys work from insert mode too,
      -- where the entry is written -- <C-c><C-c> files it, <C-c><C-n>
      -- refiles it into the knowledge base, and <prefix>w, <prefix>r,
      -- <prefix>k live on leader. org.nvim binds the configured capture
      -- mappings in normal mode only, so a <C-c> chord typed in insert mode
      -- would just leave insert mode and the entry would stay unfiled. Only
      -- the <C-c>-prefixed lhs are bound here: the <prefix> (leader) ones are
      -- normal-mode sequences that would steal ordinary typing. `sessions` is
      -- the capture registry, and a capture buffer only exists after
      -- org.capture loaded, so an org file never loads the module.
      local capture = package.loaded['org.capture']
      if capture and capture.sessions[buf] then
        local config = require 'org.config'
        local utils = require 'org.utils'
        local maps = config.opts.mappings.capture or {}
        -- the template this capture was started with: the Task one (`t`)
        -- files a ticket, every other one a note (the roam capture, `r`)
        local session = capture.sessions[buf]
        local tpl_key = session.template and session.template.key

        -- The <C-c>-prefixed capture keys are bound in both modes and as
        -- `nowait`, so a chord fires as soon as its second key is typed.
        local function add(value, fn, desc)
          for _, lhs in ipairs(config.lhs_list(value)) do
            if lhs:find '^<C%-c>' then
              for _, mode in ipairs { 'n', 'i' } do
                vim.keymap.set(mode, lhs, fn, { buffer = buf, desc = desc, nowait = true })
              end
            end
          end
        end

        local function finalize()
          utils.run(capture.finalize, buf, { jump = vim.v.count > 0 })
        end

        -- The two chords a capture carries out with: <C-c><C-c> stores the
        -- entry where its template files it (no run started -- that is
        -- `<leader>ai`'s job), and <C-c><C-n> stores it and refiles it into
        -- a node of the knowledge base picked from the roam finder
        -- (helpers/org/capture.lua `roam_refile`). Bound together, because
        -- the scheduled cleanup below has to put both back after it clears
        -- org.nvim's own <C-c> table out of the buffer.
        local function bind_chords()
          add(maps.finalize, finalize, 'org: finalize capture (count: and jump to it)')
          for _, mode in ipairs { 'n', 'i' } do
            vim.keymap.set(mode, '<C-c><C-n>', function()
              require('helpers.org.capture').roam_refile(buf)
            end, { buffer = buf, desc = 'org: refile the capture into a roam node', nowait = true })
          end
        end

        add(maps.kill, function()
          capture.kill(buf)
        end, 'org: abort capture')
        add(maps.refile, function()
          utils.run(capture.refile, buf)
        end, 'org: refile capture')
        bind_chords()

        -- A capture buffer is an org buffer, so org.nvim's own <C-c> prefix
        -- table (context action, refile, tags, clock, capture, agenda, ...)
        -- sits in it too. None of those chords belongs to a capture -- the
        -- two above are the whole table -- so every other <C-c> key is
        -- removed. Scheduled because org.nvim binds its capture keys right
        -- after the buffer's filetype is set -- after this callback, which
        -- the filetype change triggered -- and those bindings would otherwise
        -- outlive the removal.
        vim.schedule(function()
          -- only the capture's own buffer: an unnarrowed capture registers the
          -- target file, and its <C-c> chords are org.nvim's to restore.
          if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= 'acwrite' then
            return
          end
          for _, mode in ipairs { 'n', 'i' } do
            for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
              if m.lhs:lower():find '^<c%-c>' then
                pcall(vim.keymap.del, mode, m.lhs, { buffer = buf })
              end
            end
          end
          bind_chords()
        end)

        -- Normal-mode <CR> in a capture buffer opens a new line and leaves
        -- the cursor typing on it: the entry is written in insert mode, and a
        -- normal-mode key there only ever serves getting back to the text.
        -- The launch is the save's (BufWriteCmd below), not a keystroke's.
        vim.keymap.set('n', '<CR>', function()
          local lnum = vim.api.nvim_win_get_cursor(0)[1]
          local indent = (get_line(lnum) or ''):match '^[ \t]*'
          vim.api.nvim_buf_set_lines(buf, lnum, lnum, false, { indent })
          vim.api.nvim_win_set_cursor(0, { lnum + 1, #indent })
          vim.cmd 'startinsert!'
        end, { buffer = buf, desc = 'org: new line in the capture' })

        -- Saving the capture starts the run on the entry it stored. The
        -- buffer is acwrite, so `:w` is org.nvim's BufWriteCmd: it stores the
        -- entry and closes the capture, announcing the result as the User
        -- event `OrgCaptureAfterFinalize` (with the target buffer and line).
        -- This only marks the write as a launch -- the storing stays
        -- org.nvim's own -- and the hook in M.setup starts the run once the
        -- entry exists, the same launch `<leader>ai` gives. Only the Task
        -- template's capture is a ticket to run: the roam capture (`r`,
        -- <C-c><C-n>) writes a note into the knowledge base and starts
        -- nothing, so its write leaves the mark alone. The mark is dropped
        -- on the next loop, so a write that could not store anything leaves
        -- no launch armed for a later finalize.
        vim.api.nvim_create_autocmd('BufWriteCmd', {
          buffer = buf,
          callback = function()
            if tpl_key == 't' or tpl_key == nil then
              write_launch = true
              vim.schedule(function()
                write_launch = false
              end)
            end
          end,
          desc = 'org: mark the capture write as a launch',
        })

        -- The entry is typed in insert mode, but org.nvim only starts
        -- insert when it opens the buffer: coming back to it (a window
        -- switch, closing a picker) landed in normal mode. Re-enter insert
        -- on every BufEnter/WinEnter that makes the capture buffer current.
        vim.api.nvim_create_autocmd({ 'BufEnter', 'WinEnter' }, {
          buffer = buf,
          callback = function()
            if capture.sessions[buf] and vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_mode().mode == 'n' then
              vim.cmd 'startinsert'
            end
          end,
          desc = 'org: enter insert mode in a capture buffer',
        })
      end

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

      -- `c` on a headline captures a new entry under it, in the headline's
      -- own file, the same action as `c` in a TODO view (helpers/org/tree.lua
      -- bound it there first; both go through helpers/org/capture.lua
      -- `under`). Off a headline the key must stay the change operator, so
      -- the mapping is an expression: it returns `c` -- unremapped, hence
      -- the operator -- when the cursor is not on a headline, and swallows
      -- the key when it is. The capture opens a buffer, so it is deferred
      -- out of the expression's context (vim.schedule). Required at
      -- keypress, so an org file never loads the capture module.
      vim.keymap.set('n', 'c', function()
        local file = require('org.files').get_buffer(args.buf)
        local hl = file and file:headline_on(vim.api.nvim_win_get_cursor(0)[1])
        if not hl then
          return 'c'
        end
        vim.schedule(function()
          require('helpers.org.capture').under(hl, file.filename)
        end)
        return ''
      end, { buffer = args.buf, expr = true, desc = 'org: capture a child of the headline at point (else change)' })

      -- <leader>ai starts an `omp` instance for the headline at point in a
      -- tmux pane (helpers/org/ai.lua), shadowing the global plain-omp
      -- terminal key in org buffers. On a headline with open work under it --
      -- a group node, a wayfinder map -- it launches the frontier below it
      -- instead of the container itself: the tickets open with nothing open
      -- below them, one instance each (a ticket nested under another is
      -- blocked by it); on any other headline, the headline itself. On a
      -- Visual selection it launches every headline the selection covers,
      -- the same way (launch_range). <leader>aj jumps to that instance's
      -- pane when it is already running, resuming its session when it is
      -- not.
      --
      -- In an open capture buffer <leader>ai finishes the capture first and
      -- launches on the entry it stored (one key: capture, then run); the
      -- capture stays open when it could not be stored. Saving the capture
      -- (`:w`) does the same (the capture branch above), so a write is the
      -- buffer's "done" while <CR> there stays a plain new line.
      -- <leader>aj writes nothing there -- there is no ticket until the
      -- capture is filed.
      -- Normal mode only: in insert mode the leader sequence would be typed
      -- text, and org.nvim's capture buffer already re-enters insert on
      -- every return to it, so Escape first.
      vim.keymap.set('n', '<leader>ai', function()
        require('helpers.org.ai').launch()
      end, { buffer = args.buf, desc = 'org: OMP on the headline at point' })
      vim.keymap.set('x', '<leader>ai', function()
        require('helpers.org.ai').launch_range()
      end, { buffer = args.buf, desc = 'org: OMP on the selected headlines' })
      vim.keymap.set('n', '<leader>aj', function()
        require('helpers.org.ai').jump()
      end, { buffer = args.buf, desc = 'org: jump to the running OMP for the headline' })

      -- <Space><Space> (the leader twice) is the roam node finder, the
      -- same action as <leader>omf: a quick switcher for the roam sandbox
      -- without reaching into the <leader>om prefix. Buffer-local, so the
      -- plain leader sequence stays the way it is outside org files.
      vim.keymap.set('n', '<Space><Space>', function()
        require('org').action 'roam_node_find'
      end, { buffer = args.buf, desc = 'org: roam node find (<leader>omf)' })

      -- In a roam file <leader>e toggles the backlinks window (the same
      -- action as <leader>oml) instead of org.nvim's export dispatcher the
      -- key would otherwise reach there: the side window is the note's
      -- context, while export is a rare one-off. Bound only in roam files,
      -- so the other org buffers keep the export default, and the window is
      -- on the left (extensions.roam.buffer.position in org.nvim.lua).
      if is_roam(buf) then
        vim.keymap.set('n', '<leader>e', function()
          require('org').action 'roam_buffer_toggle'
        end, { buffer = buf, desc = 'org: roam backlinks window (<leader>oml)' })
      end

      -- One-key tagging and priorities (helpers/org/tagging.lua): B/F/C
      -- toggle :bug:/:feat:/:chore:, <M-a>/<M-b>/<M-c> priority A/B/C on
      -- the headline at point -- here in an org buffer (a capture buffer
      -- included); helpers/org/agenda.lua binds the same set in the agenda
      -- / TODO view.
      require('helpers.org.tagging').map(args.buf)
    end,
  })
end

return M
