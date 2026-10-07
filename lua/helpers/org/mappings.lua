-- Buffer-local org mappings for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua): normal-mode <CR> like the markdown
-- config's smart action (obsidian util.toggle_checkbox), insert-mode <CR>
-- continuing lists like bullets.vim, and dd deleting a whole subtree.
-- Registered on FileType org so they land after org.nvim attaches its own
-- buffer mappings.
local M = {}

function M.setup()
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
end

return M
