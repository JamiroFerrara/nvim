local M = {}

-- Path to Brave browser executable (WSL: Windows Brave via /mnt/c).
local BRAVE = '/mnt/c/Users/JFerrara/AppData/Local/BraveSoftware/Brave-Browser/Application/brave.exe'

--- Current visual selection as a string (charwise/linewise/blockwise).
---@return string
function M.visual_selection()
  local regions = vim.fn.getregion(vim.fn.getpos "'<", vim.fn.getpos "'>", { type = vim.fn.visualmode() })
  return vim.trim(table.concat(regions, ' '))
end

--- Open Brave with a DuckDuckGo "I'm feeling ducky" search (mirrors shell `sl`).
---@param text string
function M.brave_search(text)
  local url = 'https://duckduckgo.com/?q=!ducky+' .. vim.uri_encode(text)
  vim.fn.jobstart({ BRAVE, url }, { detach = true })
end

return M
