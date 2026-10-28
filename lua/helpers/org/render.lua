-- The org renderer's entry points (helpers/org/web): the node at the cursor
-- in a browser, and the TODO dashboard. The `O` mapping is buffer-local in
-- org files -- `o` / `O` stay the editor's own everywhere else -- and the
-- commands reach the same views from anywhere.
local M = {}

function M.setup()
  vim.api.nvim_create_user_command('OrgWeb', function()
    require('helpers.org.web').dashboard()
  end, { desc = 'Open the org TODO dashboard in the browser' })

  vim.api.nvim_create_user_command('OrgPreview', function()
    require('helpers.org.web').preview()
  end, { desc = 'Render the org node at the cursor in the browser' })

  vim.api.nvim_create_user_command('OrgWebStop', function()
    require('helpers.org.web').stop()
  end, { desc = 'Stop the org browser server' })

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
