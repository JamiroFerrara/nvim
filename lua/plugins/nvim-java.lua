return {
  'nvim-java/nvim-java',
  ft = 'java',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  config = function()
    vim.env.JAVA_HOME = os.getenv('HOME') .. '/.local/share/nvim/site/nvim-java/packages/openjdk/25/jdk-25'
    vim.env.PATH = vim.env.JAVA_HOME .. '/bin:' .. vim.env.PATH
    require('java').setup {
      jdk = {
        auto_install = false,
      },
    }
    vim.lsp.enable('jdtls')
  end,
}
