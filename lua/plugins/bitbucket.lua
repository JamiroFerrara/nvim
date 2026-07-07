return {
  dir = '~/repos/personal/plugins/bitbucket.nvim',
  cmd = 'Bitbucket',
  config = function()
    require('bitbucket').setup({
      workspace = 'novigo-consulting',
      email = 'j.ferrara@novigo-consulting.it',
      token = '',
    })
  end,
}
