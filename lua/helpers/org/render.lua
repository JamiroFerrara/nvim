-- The org renderer's entry points (helpers/org/web): the node at the cursor
-- in a browser, and the TODO dashboard. The `O` mapping is buffer-local in
-- org files -- `o` / `O` stay the editor's own everywhere else -- and the
-- commands reach the same views from anywhere.
--
-- Rendering is the renderer's: a feature that only changes how org reads
-- goes in helpers/org/web (export, then headings/markdown/highlight/clicks),
-- never in the buffer as syntax, conceal or extmarks. Nothing has to be
-- built twice -- the browser is the view that gets the work, and the editor
-- stays the editor. The buffer-side rendering that predates this rule
-- (helpers/org/decorations, blocks, callouts, links) stays as it is.
local M = {}

function M.setup()
  vim.api.nvim_create_user_command('OrgWeb', function()
    require('helpers.org.web').dashboard()
  end, { desc = 'Open the org TODO dashboard in the browser' })

  vim.api.nvim_create_user_command('OrgPreview', function()
    require('helpers.org.web').preview()
  end, { desc = 'Render the org node at the cursor in the browser' })

  vim.api.nvim_create_user_command('OrgRoam', function()
    require('helpers.org.web').roam()
  end, { desc = 'Open the org-roam notes and link graph in the browser' })

  vim.api.nvim_create_user_command('OrgWebShare', function()
    require('helpers.org.web').share()
  end, { desc = 'Open the org dashboard on your phone (ngrok link and QR)' })

  vim.api.nvim_create_user_command('OrgWebStop', function()
    require('helpers.org.web').stop()
  end, { desc = 'Stop the org browser server' })

  vim.api.nvim_create_user_command('OrgWebReload', function()
    local ok, err = require('helpers.org.web').reload()
    if not ok then
      vim.notify('org web: ' .. tostring(err), vim.log.levels.WARN)
    end
  end, { desc = 'Read the org web pages again without restarting the server or the tunnel' })

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('OrgRender', { clear = true }),
    pattern = { 'org' },
    callback = function(args)
      vim.keymap.set('n', 'O', function()
        require('helpers.org.web').preview(args.buf)
      end, { buffer = args.buf, desc = 'org: render this node in the browser' })
    end,
  })
end

return M
