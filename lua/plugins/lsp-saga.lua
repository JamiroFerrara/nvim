return {
  'nvimdev/lspsaga.nvim',
  event = 'VeryLazy',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  opts = {},
  config = function(_, opts)
    require('lspsaga').setup(opts)

    -- lspsaga.symbol.head starts a 500ms uv timer on every LspNotify
    -- didChange (buf_watcher) and resolves the buffer URI inside the
    -- scheduled callback (do_request), so a buffer wiped in that window
    -- aborts with "Invalid buffer id: N" from vim.uri_from_bufnr. Saving an
    -- org capture hits it every time: org.nvim's own LSP server attaches to
    -- the `filetype=org` capture buffer and the buffer is deleted the moment
    -- it is written (buftype=acwrite, bufhidden=wipe). Skip the request when
    -- the buffer is gone; nothing reads symbols for it any more.
    local api = vim.api
    local head = require 'lspsaga.symbol.head'
    local do_request = head.do_request
    head.do_request = function(self, buf, client_id)
      if api.nvim_buf_is_valid(buf) and api.nvim_buf_is_loaded(buf) then
        return do_request(self, buf, client_id)
      end
    end
  end,
  dependencies = {
    'nvim-treesitter/nvim-treesitter', -- optional
    'nvim-tree/nvim-web-devicons', -- optional
  },
}
