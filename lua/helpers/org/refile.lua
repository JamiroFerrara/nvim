-- Capture-refile fix for org.nvim (wired in
-- lua/terminal_plugins/org.nvim.lua). org-capture-refile (<prefix>r in the
-- capture buffer) stores the entry in the template's target
-- (default_notes_file, refile.org) and then refiles it to the chosen target.
-- org.nvim saves the refile destination but not the store buffer the move
-- emptied (refile.lua saves the source only with `opts.save`, which the
-- capture path does not pass), so the block stayed in refile.org on disk.
-- Save that buffer once the refile succeeded. The wrapper is installed when
-- org.capture first loads, so that module stays out of startup.
local M = {}

function M.setup()
  require('org.lazy').on_load('org.capture', 'save_emptied_store', function(capture)
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
  end)
end

return M
