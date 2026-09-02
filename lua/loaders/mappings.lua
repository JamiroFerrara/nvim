local mappings = require 'mappings'

-- Normalize a mapping value into `(rhs, opts)`.
-- Values are a plain string, a function, or a `{ rhs, desc = ... }` table.
local function normalize(value)
  if type(value) == 'table' then
    local opts = {}
    if value.desc then
      opts.desc = value.desc
    end
    return value[1], opts
  end
  return value, {}
end

for mode, defs in pairs(mappings) do
  if mode == 'tn' then
    -- Terminal-normal mappings apply buffer-locally once a terminal opens
    vim.api.nvim_create_autocmd('TermOpen', {
      callback = function(args)
        for key, value in pairs(defs) do
          local rhs, opts = normalize(value)
          opts.buffer = args.buf
          opts.silent = true
          vim.keymap.set('n', key, rhs, opts)
        end
      end,
    })
  else
    for key, value in pairs(defs) do
      local rhs, opts = normalize(value)
      opts.silent = true
      vim.keymap.set(mode, key, rhs, opts)
    end
  end
end
