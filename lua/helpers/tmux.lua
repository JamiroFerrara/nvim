local M = {}

function M.move_bottom()
  local is_open = require('helpers.telescope').is_telescope_open()
  if is_open then
  else
    require('tmux').move_bottom();
  end
end

return M;
