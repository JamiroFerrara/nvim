return {
  "huantrinh1802/m_taskwarrior_d.nvim",
  version = "*",
  enabled = true,
  dependencies = { "MunifTanjim/nui.nvim" },
  config = function()
    -- Require
    require("m_taskwarrior_d").setup({
      display_due_or_scheduled = false, -- Display due or scheduled tasks in the task list
    })
    -- Optional
    vim.api.nvim_set_keymap("n", "<leader>te", "<cmd>TWEditTask<cr>",
      { desc = "TaskWarrior Edit", noremap = true, silent = true })
    vim.api.nvim_set_keymap("n", "<leader>tv", "<cmd>TWView<cr>", { noremap = true, silent = true })
    vim.api.nvim_set_keymap("n", "<leader>tu", "<cmd>TWUpdateCurrent<cr>", { noremap = true, silent = true })
    vim.api.nvim_set_keymap("n", "<leader>ts", "<cmd>TWSyncTasks<cr>", { noremap = true, silent = true })

    -- WARNING: it may be slow to open large files, because it scan the whole buffer
    -- PERF: Figure out some performance hacks
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
      group = vim.api.nvim_create_augroup("TWTask", { clear = true }),
      pattern = "*.md,*.markdown",
      callback = function()
        local excluded_paths = { "~/.config", "~/.local" } -- Add substrings of paths to ignore
        local buf_path = vim.api.nvim_buf_get_name(0)

        for _, path in ipairs(excluded_paths) do
          if string.find(buf_path, path, 1, true) then
            return
          end
        end

        vim.cmd('TWSyncTasks')
        vim.cmd('TWBufQueryTasks')
      end,
    })
  end,
}
