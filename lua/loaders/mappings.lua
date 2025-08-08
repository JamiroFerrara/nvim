local mappings = require 'mappings'

for mode, mode_mappings in pairs(mappings) do
  if mode == 'tn' then
    -- Terminal normal mode mappings
    vim.api.nvim_create_autocmd('TermOpen', {
      callback = function(args)
        for key, actions in pairs(mode_mappings) do
          local opts = { buffer = args.buf, silent = true, noremap = true }
          if not actions then
            vim.keymap.set('n', key, '', opts)
          elseif type(actions) == 'function' then
            vim.keymap.set('n', key, actions, opts)
          elseif type(actions) == 'string' then
            vim.keymap.set('n', key, actions, opts)
          elseif type(actions) == 'table' then
            local action_string = table.concat(actions, '<bar>')
            vim.keymap.set('n', key, action_string, opts)
          else
            vim.notify(('Unsupported mapping type for %s in mode %s'):format(key, mode), vim.log.levels.WARN)
          end
        end
      end,
    })
  else
    -- Normal mappings
    for key, actions in pairs(mode_mappings) do
      local opts = { silent = true }
      if not actions then
        vim.keymap.set(mode, key, '', opts)
      elseif type(actions) == 'function' then
        vim.keymap.set(mode, key, actions, opts)
      elseif type(actions) == 'string' then
        vim.keymap.set(mode, key, actions, opts)
      elseif type(actions) == 'table' then
        local action_string = table.concat(actions, '<bar>')
        vim.keymap.set(mode, key, action_string, opts)
      else
        vim.notify(('Unsupported mapping type for %s in mode %s'):format(key, mode), vim.log.levels.WARN)
      end
    end
  end
end

