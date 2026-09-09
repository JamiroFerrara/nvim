local M = {}

-- A terminal buffer is named `term://{cwd}//{pid}:{shell}`. When you jump away
-- from one (open a file, etc.), Neovim records that buffer in the jumplist and
-- persists it in shada. On the next nvim instance <C-o> (jumplist back, mapped
-- to <A-o>) lands on the entry and spawns a fresh terminal at the stale {cwd}
-- instead of the project root.
--
-- Deleting the job-less `term://` buffers that shada restores removes those
-- entries from the jumplist entirely, so <C-o> only navigates real files.
function M.clean_restored_terminals()
  local ok, jl = pcall(vim.fn.getjumplist)
  if not ok then
    return
  end
  local entries = jl and jl[1]
  if type(entries) ~= 'table' then
    return
  end
  for _, e in ipairs(entries) do
    if type(e) == 'table' then
      local bufnr = e.bufnr
      local name = e.filename
      if not name and type(bufnr) == 'number' and vim.api.nvim_buf_is_valid(bufnr) then
        name = vim.api.nvim_buf_get_name(bufnr)
      end
      if type(name) == 'string' and name:match '^term://' then
        if type(bufnr) == 'number' and vim.api.nvim_buf_is_valid(bufnr) then
          -- A restored entry has no running job; a live terminal does.
          if vim.b[bufnr].terminal_job_id == nil then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
          end
        end
      end
    end
  end
end

return M
