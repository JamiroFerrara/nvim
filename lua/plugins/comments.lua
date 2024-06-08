return {
  'folke/todo-comments.nvim',
  event = 'BufReadPre',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'numToStr/Comment.nvim',
  },
  opts = { signs = false },
}
