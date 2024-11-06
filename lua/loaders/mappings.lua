local mappings = require 'mappings'
for mode, mode_mappings in pairs(mappings) do
  for key, actions in pairs(mode_mappings) do
    -- Check if the actions are defined
    if actions then
      -- If there's only one action, convert it to a string
      if type(actions) == 'string' then
        vim.keymap.set(mode, key, actions, { silent = true })
      else
        -- If there are multiple actions, unpack them from the table
        local action_string = table.concat(actions, '<bar>')
        vim.keymap.set(mode, key, action_string, { silent = true })
      end
    else
      -- If actions are set to false, disable the mapping
      vim.keymap.set(mode, key, '', { silent = true })
    end
  end
end
