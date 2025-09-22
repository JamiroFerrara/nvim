-- lazy.nvim

math.randomseed(os.time())
local quotes = {
  "wake up neo.",
  "Unfortunately, no one can be told what the Matrix is. \n You have to see it for yourself.",
  "Fate, it seems, is not without a sense of irony",
  "Guns, lots of guns",
  "I’m trying to free your mind, Neo. But I can only show you the door. \n You’re the one that has to walk through it",
  "I don’t like the idea that I’m not in control of my life",
  "What are you waiting for? \n You’re faster than this. Don’t think you are, know you are.",
  "If real is what you can feel, smell, taste and see, \n then ‘real’ is simply electrical signals interpreted by your brain",
  "Stop trying to hit me and hit me!",
  "I know Kung Fu.",
  "There is no spoon.",
  "You take the red pill, you stay in Wonderland, \n and I show you how deep the rabbit hole goes.",
  "Welcome to the real world.",
  "I can only show you the door. You’re the one who has to walk through it.",
  "Ignorance is bliss.",
  "The body cannot live without the mind.",
  "To deny our own impulses is to deny the very thing that makes us human.",
  "You have a problem with authority, Mr. Anderson.",
  "Not like this. Not like this.",
  "There is no escaping reason; no denying purpose.",
  "Neo, sooner or later you’re going to realize, \n just as I did, there’s a difference between knowing the path, \n and walking the path.",
  "Hope. It is the quintessential human delusion, \n simultaneously the source of your greatest strength and your greatest weakness.",
  "Choice is an illusion created between those with power and those without.",
  "What do men with power want? More power.",
  "I’m going to show them a world... \n where anything is possible.",
  "You hear that Mr. Anderson? That is the sound of inevitability.",
  "What if tomorrow the war could be over?",
  "The Matrix cannot tell you who you are.",
  "Every mammal on this planet instinctively develops a natural equilibrium with the surrounding environment.",
  "I know why you can’t sleep. I know what you’ve been doing.",
  "There is a difference between knowing the path and walking the path.",
  "It's unlike anything we've seen before.",
  "Never send a human to do a machine's job.",
  "Zion will fall.",
  "I'm trying to free your mind, Neo.",
  "What do all men with power want?",
  "Why, Mr. Anderson, why?",
  "The program Smith has grown beyond your control.",
  "What is 'real'? How do you define 'real'?",
  "I think we can handle one little girl.",
  "Denial is the most predictable of all human responses.",
  "I believe this night holds for each and every one of us, the very meaning of our lives.",
  "The Matrix is a world that has been pulled over your eyes.",
  "I want the same thing you want, Neo, and I am willing to go as far as you are.",
  "I have dreamed a dream, but now that my dream is over.",
  "As you can see, we've had our eye on you for some time now, Mr. Anderson.",
  "They’re watching you, Neo.",
  "It's the question that drives us, Neo."
}

return {
  "folke/snacks.nvim",
  ---@type snacks.Config
  opts = {
    dashboard = {
      width = 60,
      row = nil,                                                                   -- dashboard position. nil for center
      col = nil,                                                                   -- dashboard position. nil for center
      pane_gap = 4,                                                                -- empty columns between vertical panes
      autokeys = "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ", -- autokey sequence
      -- These settings are used by some built-in sections
      preset = {
        -- Defaults to a picker that supports `fzf-lua`, `telescope.nvim` and `mini.pick`
        ---@type fun(cmd:string, opts:table)|nil
        pick = nil,
        -- Used by the `keys` section to show keymaps.
        -- Set your custom keymaps here.
        -- When using a function, the `items` argument are the default keymaps.
        ---@type snacks.dashboard.Item[]
        keys = {
          -- { icon = " ", key = "f", desc = "Find File", action = ":lua Snacks.dashboard.pick('files')" },
          -- { icon = " ", key = "n", desc = "New File", action = ":ene | startinsert" },
          -- { icon = " ", key = "g", desc = "Find Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
          -- { icon = " ", key = "r", desc = "Recent Files", action = ":lua Snacks.dashboard.pick('oldfiles')" },
          -- { icon = " ", key = "c", desc = "Config", action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
          -- { icon = " ", key = "s", desc = "Restore Session", section = "session" },
          -- { icon = "󰒲 ", key = "L", desc = "Lazy", action = ":Lazy", enabled = package.loaded.lazy ~= nil },
          -- { icon = " ", key = "q", desc = "Quit", action = ":qa" },
        },
        -- Used by the `header` section
        header = quotes[math.random(#quotes)]
      },
      -- item field formatters
      formats = {
        icon = function(item)
          if item.file and item.icon == "file" or item.icon == "directory" then
            return M.icon(item.file, item.icon)
          end
          return { item.icon, width = 2, hl = "icon" }
        end,
        footer = { "%s", align = "center" },
        header = { "%s", align = "center" },
        file = function(item, ctx)
          local fname = vim.fn.fnamemodify(item.file, ":~")
          fname = ctx.width and #fname > ctx.width and vim.fn.pathshorten(fname) or fname
          if #fname > ctx.width then
            local dir = vim.fn.fnamemodify(fname, ":h")
            local file = vim.fn.fnamemodify(fname, ":t")
            if dir and file then
              file = file:sub(-(ctx.width - #dir - 2))
              fname = dir .. "/…" .. file
            end
          end
          local dir, file = fname:match("^(.*)/(.+)$")
          return dir and { { dir .. "/", hl = "dir" }, { file, hl = "file" } } or { { fname, hl = "file" } }
        end,
      },
      sections = {
        -- { section = "startup" },
        { section = "header" },
        function()
          local in_git = Snacks.git.get_root() ~= nil
          local cmds = {
            {
              icon = " ",
              title = "Git Status",
              cmd = "git --no-pager diff --stat -B -M -C",
              height = 5,
            },
          }
          return vim.tbl_map(function(cmd)
            return vim.tbl_extend("force", {
              pane = 1,
              section = "terminal",
              enabled = in_git,
              -- padding = 1,
              -- ttl = 5 * 60,
              indent = 3,
            }, cmd)
          end, cmds)
        end,
      },
    }
  }
}
