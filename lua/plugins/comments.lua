return {
  'folke/todo-comments.nvim',
  event = 'BufReadPre',
  lazy = true,
  dependencies = {
    'nvim-lua/plenary.nvim',
    'numToStr/Comment.nvim',
  },
  opts = { signs = false },
}
