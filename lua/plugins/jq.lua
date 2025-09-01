return {
  'JamiroFerrara/jq.nvim',
  -- event = 'VeryLazy',
  cmd = {
    'JqVisual',
    'JqFile',
  },
  config = function()
    require('jq').setup()
  end,
}
