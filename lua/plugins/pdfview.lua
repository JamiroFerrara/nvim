return {
  "basola21/PDFview",
  cmd = "PDFview",
  event = "VeryLazy",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    -- Increase page size: default 50 → 120 lines per page
    local renderer = require('pdfview.renderer')
    local orig_paginate = renderer.paginate_text
    renderer.paginate_text = function(text, _)
      return orig_paginate(text, 10000)
    end

    -- Buffer-local mappings for PDF buffers: H = previous, L = next page
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "pdfview",
      callback = function(ev)
        local buf = ev.buf
        vim.keymap.set("n", "H", function() require('pdfview.renderer').previous_page() end,
          { buffer = buf, desc = "PDFview: Previous page" })
        vim.keymap.set("n", "L", function() require('pdfview.renderer').next_page() end,
          { buffer = buf, desc = "PDFview: Next page" })
      end,
    })

    -- NOTE: This must be installed
    -- sudo apt install poppler-utils
    vim.api.nvim_create_autocmd("BufReadPost", {
      pattern = "*.pdf",
      callback = function()
        local file_path = vim.api.nvim_buf_get_name(0)
        require("pdfview").open(file_path)
      end,
    })
  end
}
