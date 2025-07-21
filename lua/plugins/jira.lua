return {
  'Funk66/jira.nvim',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('jira').setup {
      domain = 'novigo.atlassian.net/',
      user = 'j.ferrara@novigo-consulting.it',
      token = '',
      key = { 'IT' },
    }
  end,
  cond = function()
    return vim.env.JIRA_API_TOKEN ~= nil
  end,
  keys = {
    {
      '<leader>jv',
      function()
        -- Get the visual selection using register
        local old_reg = vim.fn.getreg '"'
        local old_regtype = vim.fn.getregtype '"'

        -- Yank the visual selection to register
        vim.cmd 'normal! gv"*y'
        local selection = vim.fn.getreg '*'
        vim.notify(selection, vim.log.levels.WARN);

        -- Restore the register
        vim.fn.setreg('"', old_reg, old_regtype)

        if selection then
          vim.cmd('JiraView ' .. selection)
        else
          vim.notify('No Jira issue key found in selection: ' .. selection, vim.log.levels.WARN)
        end
      end,
      desc = 'View Jira issue from visual selection',
      mode = 'n',
      silent = true,
    },
    { '<leader>jo', ':JiraOpen<cr>', desc = 'Open Jira issue in browser', silent = true },
  },
}
