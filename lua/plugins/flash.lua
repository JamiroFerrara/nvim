return {
  'folke/flash.nvim',
  event = 'VeryLazy',
  enabled = not _G.NVIM_TERMINAL_ONLY,
  ---@type Flash.Config
  opts = {
    -- labels = "abcdefghijklmnopqrstuvwxyz",
    labels = 'asdfghjklqwertyuiopzxcvbnm',
    search = {
      -- search/jump in all windows
      multi_window = true,
      -- search direction
      forward = true,
      -- when `false`, find only matches in the given direction
      wrap = true,
      ---@type flash.pattern.mode
      -- each mode will take ignorecase and smartcase into account.
      -- * exact: exact match
      -- * search: regular search
      -- * fuzzy: fuzzy search
      -- * fun(str): custom function that returns a pattern
      --   for example, to only match at the beginning of a word:
      --   mode = function(str)
      --     return "\\<" .. str
      --   end,
      mode = 'exact',
      -- behave like `incsearch`
      incremental = false,
      -- excluded filetypes and custom window filters
      ---@type (string|fun(win:window))[]
      exclude = {
        'notify',
        'cmp_menu',
        'noice',
        'flash_prompt',
        function(win)
          -- exclude non-focusable windows
          return not vim.api.nvim_win_get_config(win).focusable
        end,
      },
      -- optional trigger character that needs to be typed before
      -- a jump label can be used. it's not recommended to set this,
      -- unless you know what you're doing
      trigger = '',
      -- max pattern length. if the pattern length is equal to this
      -- labels will no longer be skipped. when it exceeds this length
      -- it will either end in a jump or terminate the search
      max_length = nil, ---@type number?
    },
    jump = {
      -- save location in the jumplist
      jumplist = true,
      -- jump position
      pos = 'start', ---@type "start" | "end" | "range"
      -- add pattern to search history
      history = false,
      -- add pattern to search register
      register = false,
      -- clear highlight after jump
      nohlsearch = false,
      -- automatically jump when there is only one match
      autojump = true,
      -- you can force inclusive/exclusive jumps by setting the
      -- `inclusive` option. by default it will be automatically
      -- set based on the mode.
      inclusive = nil, ---@type boolean?
      -- jump position offset. not used for range jumps.
      -- 0: default
      -- 1: when pos == "end" and pos < current position
      offset = nil, ---@type number
    },
    label = {
      -- allow uppercase labels
      uppercase = true,
      -- add a label for the first match in the current window.
      -- you can always jump to the first match with `<cr>`
      current = true,
      -- show the label after the match
      after = true, ---@type boolean|number[]
      -- show the label before the match
      before = false, ---@type boolean|number[]
      -- position of the label extmark
      style = 'overlay', ---@type "eol" | "overlay" | "right_align" | "inline"
      -- flash tries to re-use labels that were already assigned to a position,
      -- when typing more characters. by default only lower-case labels are re-used.
      reuse = 'lowercase', ---@type "lowercase" | "all"
      -- for the current window, label targets closer to the cursor first
      distance = true,
      -- minimum pattern length to show labels
      -- ignored for custom labelers.
      min_pattern_length = 0,
      -- enable this to use rainbow colors to highlight labels
      -- can be useful for visualizing treesitter ranges.
      rainbow = {
        enabled = false,
        -- number between 1 and 9
        shade = 5,
      },
      -- with `format`, you can change how the label is rendered.
      -- should return a list of `[text, highlight]` tuples.
      ---@class flash.format
      ---@field state flash.state
      ---@field match flash.match
      ---@field hl_group string
      ---@field after boolean
      ---@type fun(opts:flash.format): string[][]
      format = function(opts)
        return { { opts.match.label, opts.hl_group } }
      end,
    },
    highlight = {
      -- show a backdrop with hl flashbackdrop
      backdrop = false,
      -- highlight the search matches
      matches = true,
      -- extmark priority
      priority = 5000,
      groups = {
        match = 'flashmatch',
        current = 'flashcurrent',
        backdrop = 'flashbackdrop',
        label = 'flashlabel',
      },
    },
    -- action to perform when picking a label.
    -- defaults to the jumping logic depending on the mode.
    ---@type fun(match:flash.match, state:flash.state)|nil
    action = nil,
    -- initial pattern to use when opening flash
    pattern = '',
    -- when `true`, flash will try to continue the last search
    continue = false,
    -- you can override the default options for a specific mode.
    -- use it with `require("flash").jump({mode = "forward"})`
    ---@type table<string, flash.config>
    modes = {
      -- options used when flash is activated through
      -- a regular search with `/` or `?`
      search = {
        enabled = true, -- enable flash for search
        highlight = { backdrop = false },
        jump = { history = true, register = true, nohlsearch = true },
        search = {
          -- `forward` will be automatically set to the search direction
          -- `mode` is always set to `search`
          -- `incremental` is set to `true` when `incsearch` is enabled
        },
      },
      -- options used when flash is activated through
      -- `f`, `f`, `t`, `t`, `;` and `,` motions
      char = {
        enabled = false,
        -- by default all keymaps are enabled, but you can disable some of them,
        -- by removing them from the list.
        keys = { 't', 't', ';', ',' },
        search = { wrap = false },
        highlight = { backdrop = false },
        jump = { register = false },
      },
      -- options used for treesitter selections
      -- `require("flash").treesitter()`
      treesitter = {
        labels = 'abcdefghijklmnopqrstuvwxyz',
        jump = { pos = 'range' },
        search = { incremental = false },
        label = { before = true, after = true, style = 'inline' },
        highlight = {
          backdrop = false,
          matches = false,
        },
      },
      treesitter_search = {
        jump = { pos = 'range' },
        search = { multi_window = true, wrap = true, incremental = false },
        remote_op = { restore = true },
        label = { before = true, after = true, style = 'inline' },
      },
      -- options used for remote flash
      remote = {
        remote_op = { restore = true, motion = true },
      },
    },
    -- options for the floating window that shows the prompt,
    -- for regular jumps
    prompt = {
      enabled = true,
      prefix = { { '⚡', 'flashprompticon' } },
      win_config = {
        relative = 'editor',
        width = 1, -- when <=1 it's a percentage of the editor width
        height = 1,
        row = -1, -- when negative it's an offset from the bottom
        col = 0, -- when negative it's an offset from the right
        zindex = 1000,
      },
    },
    -- options for remote operator pending mode
    remote_op = {
      -- restore window views and cursor position
      -- after doing a remote operation
      restore = false,
      -- for `jump.pos = "range"`, this setting is ignored.
      -- `true`: always enter a new motion when doing a remote operation
      -- `false`: use the window's cursor position and jump target
      -- `nil`: act as `true` for remote windows, `false` for the current window
      motion = false,
    },
  },
  specs = {
    {
      "folke/snacks.nvim",
      opts = {
        picker = {
          win = {
            input = {
              keys = {
                ["<C-f>"] = { "flash", mode = { "n", "i" } },
                -- ["<C-x>"] = { "flash" },
              },
            },
          },
          actions = {
            flash = function(picker)
              require("flash").jump({
                pattern = "^",
                label = { after = { 0, 0 } },
                search = {
                  mode = "search",
                  exclude = {
                    function(win)
                      return vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "snacks_picker_list"
                    end,
                  },
                },
                action = function(match)
                  local idx = picker.list:row2idx(match.pos[1])
                  picker.list:_move(idx, true, true)
                end,
              })
            end,
          },
        },
      },
    },
  },
  -- stylua: ignore
  keys = {
    -- { "f", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
    -- { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
    -- { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
    -- { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
    -- { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
  },
}
