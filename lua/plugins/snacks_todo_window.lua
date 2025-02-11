local function getTodoWindow(w, h)
  local cwd = vim.fn.getcwd()
  local path = cwd .. '/TODO.md'
  Snacks.win {
    file = path,
    width = w,
    height = h,
    title = 'TODO',
    position = 'float',
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
      {
        '<C-t>',
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
end

return {
  'folke/snacks.nvim',
  keys = {
    {
      -- TODO togglable window
      '<A-t>',
      function() getTodoWindow(0.5, 0.5)end,
      desc = 'Buffers',
    },
    {
      -- TODO togglable window
      '<C-t>',
      function() getTodoWindow(0.5, 0.5)end,
      desc = 'Buffers',
    },
  },
}
