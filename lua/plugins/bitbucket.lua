return {
  dir = '~/repos/personal/plugins/bitbucket.nvim',
  cmd = 'Bitbucket',
  config = function()
    require('bitbucket').setup({
      workspace = 'novigo-consulting',
      email = 'j.ferrara@novigo-consulting.it',
      token = 'ATATT3xFfGF0mPrfepHrOQlpiz-RhiRhoQNJEFYK3lP19PyXjeYfjZhIItQQzHjH1LjF7uhy2QFa5q7HZKvzyYL9ujOqZZC5kX3iRNZv_SDlIKnuy0yRpVAJpG0ee2vSIz1azlWxechqipOp3EEkqhbN25dCQvD9RnJnjUh6FYwZm6g-sxpeAGQ=EE83E842',
    })
  end,
}
