return {
  'JamiroFerrara/jq.nvim',
  event = 'VeryLazy',
  config = function()
    require('jq').setup()
  end
}
