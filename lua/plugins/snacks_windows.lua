return {
  'folke/snacks.nvim',
  keys = {
    {
      -- TODO togglable window
      '<A-t>',
      function()
        local cwd = vim.fn.getcwd()
        local path = cwd .. '/TODO.md'
        Snacks.win {
          file = path,
          width = 0.5,
          height = 0.5,
          title = 'TODO',
          position = 'right',
          -- fixed = false,
          fixbuf = false,
          bo = {
            modifiable = true,
          },
          keys = {
            {
              '<A-t>',
              function()
                vim.api.nvim_command ':q'
              end,
              mode = 'n',
              desc = 'Close TODO',
            },
          },
          border = 'single',
          wo = {
            spell = false,
            wrap = false,
            signcolumn = 'yes',
            statuscolumn = ' ',
            conceallevel = 3,
          },
        }
      end,
      desc = 'Buffers',
    },
  },
}
