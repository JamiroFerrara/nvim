local M = {}

function M.move_bottom()
  pcall(vim.api.nvim_command, "doautocmd User event_tmux")
  local is_open = require('helpers.telescope').is_telescope_open()
  if is_open then
  else
    require('tmux').move_bottom();
  end
end

function M.move_top()
  pcall(vim.api.nvim_command, "doautocmd User event_tmux")
  local is_open = require('helpers.telescope').is_telescope_open()
  if is_open then
  else
    require('tmux').move_bottom();
  end
end

function M.move_left()
  pcall(vim.api.nvim_command, "doautocmd User event_tmux")
  local is_open = require('helpers.telescope').is_telescope_open()
  if is_open then
  else
    require('tmux').move_bottom();
  end
end

function M.move_right()
  pcall(vim.api.nvim_command, "doautocmd User event_tmux")
  local is_open = require('helpers.telescope').is_telescope_open()
  if is_open then
  else
    require('tmux').move_bottom();
  end
end

return M;
