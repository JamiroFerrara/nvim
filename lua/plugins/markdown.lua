return {
  'MeanderingProgrammer/markdown.nvim',
  -- event = 'VeryLazy',
  -- enabled = not _G.NVIM_TERMINAL_ONLY,
  main = 'render-markdown',
  ft = 'markdown',
  opts = {
    heading = {
      -- Turn on / off heading icon & background rendering
      enabled = true,
      -- Turn on / off any sign column related rendering
      sign = true,
      -- Replaces '#+' of 'atx_h._marker'
      -- The number of '#' in the heading determines the 'level'
      -- The 'level' is used to index into the array using a cycle
      -- The result is left padded with spaces to hide any additional '#'
      icons = { '● ', '● ', '● ', '● ', '● ', '● ' },
      -- Added to the sign column if enabled
      -- The 'level' is used to index into the array using a cycle
      signs = { '󰫎 ' },
      -- Width of the heading background:
      --  block: width of the heading text
      --  full: full width of the window
      width = 'full',
      -- -- The 'level' is used to index into the array using a clamp
      -- -- Highlight for the heading icon and extends through the entire line
      backgrounds = {
        '@markup.heading.1.markdown',
        '@markup.heading.2.markdown',
        '@markup.heading.3.markdown',
        '@markup.heading.4.markdown',
        '@markup.heading.5.markdown',
        '@markup.heading.6.markdown',
      },
      -- -- The 'level' is used to index into the array using a clamp
      -- -- Highlight for the heading and sign icons
      foregrounds = {
        'RenderMarkdownH1',
        'RenderMarkdownH2',
        'RenderMarkdownH3',
        'RenderMarkdownH4',
        'RenderMarkdownH5',
        'RenderMarkdownH6',
      },
    },
    code = {
      -- Turn on / off code block & inline code rendering
      enabled = true,
      -- Turn on / off any sign column related rendering
      sign = true,
      -- Determines how code blocks & inline code are rendered:
      --  none: disables all rendering
      --  normal: adds highlight group to code blocks & inline code, adds padding to code blocks
      --  language: adds language icon to sign column if enabled and icon + name above code blocks
      --  full: normal + language
      style = 'full',
      -- Amount of padding to add to the left of code blocks
      left_pad = 0,
      -- Amount of padding to add to the right of code blocks when width is 'block'
      right_pad = 0,
      -- Width of the code block background:
      --  block: width of the code block
      --  full: full width of the window
      width = 'full',
      -- Determins how the top / bottom of code block are rendered:
      --  thick: use the same highlight as the code body
      --  thin: when lines are empty overlay the above & below icons
      border = 'thick',
      -- Used above code blocks for thin border
      above = '▄',
      -- Used below code blocks for thin border
      below = '▀',
      --FIX: Highlight for code blocks & inline code
      highlight = '',
      highlight_inline = '',
    },
    dash = {
      -- Turn on / off thematic break rendering
      enabled = true,
      -- Replaces '---'|'***'|'___'|'* * *' of 'thematic_break'
      -- The icon gets repeated across the window's width
      icon = '─',
      -- Width of the generated line:
      --  <integer>: a hard coded width value
      --  full: full width of the window
      width = 'full',
      -- Highlight for the whole line generated from the icon
      highlight = 'RenderMarkdownDash',
    },
    bullet = {
      -- Turn on / off list bullet rendering
      enabled = true,
      -- Replaces '-'|'+'|'*' of 'list_item'
      -- How deeply nested the list is determines the 'level'
      -- The 'level' is used to index into the array using a cycle
      -- If the item is a 'checkbox' a conceal is used to hide the bullet instead
      icons = { '●', '○', '◆', '◇' },
      -- Padding to add to the right of bullet point
      right_pad = 0,
      -- Highlight for the bullet icon
      highlight = 'RenderMarkdownBullet',
    },
    -- Checkboxes are a special instance of a 'list_item' that start with a 'shortcut_link'
    -- There are two special states for unchecked & checked defined in the markdown grammar
    checkbox = {
      -- Turn on / off checkbox state rendering
      enabled = true,
      unchecked = {
        icon = '- ',
        highlight = 'ObsidianTodo',
      },
      checked = {
        icon = '- ',
        highlight = 'ObsidianDone',
      },
      custom = {
        started = { raw = "[>]", rendered = "- ", highlight = "@markup.raw" },
        deleted = { raw = "[~]", rendered = "- ", highlight = "@markup.raw" },
        question = { raw = '[?]', rendered = '- ', highlight = '@comment.warning.gitcommit' },
        -- warning = { raw = '[!]', rendered = '- ', highlight = '@comment.warning.gitcommit' },
      },
    },
    quote = {
      -- Turn on / off block quote & callout rendering
      enabled = true,
      -- Replaces '>' of 'block_quote'
      icon = '▋',
      -- Highlight for the quote icon
      highlight = 'RenderMarkdownBullet',
    },
    pipe_table = {
      -- Turn on / off pipe table rendering
      enabled = true,
      -- Determines how the table as a whole is rendered:
      --  none: disables all rendering
      --  normal: applies the 'cell' style rendering to each row of the table
      --  full: normal + a top & bottom line that fill out the table when lengths match
      style = 'full',
      -- Determines how individual cells of a table are rendered:
      --  overlay: writes completely over the table, removing conceal behavior and highlights
      --  raw: replaces only the '|' characters in each row, leaving the cells unmodified
      --  padded: raw + cells are padded with inline extmarks to make up for any concealed text
      cell = 'padded',
      -- Gets placed in delimiter row for each column, position is based on alignmnet
      alignment_indicator = '━',
        -- Characters used to replace table border
        -- Correspond to top(3), delimiter(3), bottom(3), vertical, & horizontal
        -- stylua: ignore
        border = {
            '┌', '┬', '┐',
            '├', '┼', '┤',
            '└', '┴', '┘',
            '│', '─',
        },
      -- Highlight for table heading, delimiter, and the line above
      head = 'RenderMarkdownTableHead',
      -- Highlight for everything else, main table rows and the line below
      row = 'RenderMarkdownTableRow',
      -- Highlight for inline padding used to add back concealed space
      filler = 'RenderMarkdownTableFill',
    },
    callout = {
      note = { raw = '[!NOTE]', rendered = '󰋽 Note', highlight = 'RenderMarkdownInfo' },
      tip = { raw = '[!TIP]', rendered = '󰌶 Tip', highlight = 'RenderMarkdownSuccess' },
      important = { raw = '[!IMPORTANT]', rendered = '󰅾 Important', highlight = 'RenderMarkdownHint' },
      warning = { raw = '[!WARNING]', rendered = '󰀪 Warning', highlight = 'RenderMarkdownWarn' },
      caution = { raw = '[!CAUTION]', rendered = '󰳦 Caution', highlight = 'RenderMarkdownError' },
      -- Obsidian: https://help.a.md/Editing+and+formatting/Callouts
      abstract = { raw = '[!ABSTRACT]', rendered = '󰨸 Abstract', highlight = 'RenderMarkdownInfo' },
      todo = { raw = '[!TODO]', rendered = '󰗡 Todo', highlight = 'RenderMarkdownInfo' },
      success = { raw = '[!SUCCESS]', rendered = '󰄬 Success', highlight = 'RenderMarkdownSuccess' },
      question = { raw = '[!QUESTION]', rendered = '󰘥 Question', highlight = 'RenderMarkdownWarn' },
      failure = { raw = '[!FAILURE]', rendered = '󰅖 Failure', highlight = 'RenderMarkdownError' },
      danger = { raw = '[!DANGER]', rendered = '󱐌 Danger', highlight = 'RenderMarkdownError' },
      bug = { raw = '[!BUG]', rendered = '󰨰 Bug', highlight = 'RenderMarkdownError' },
      example = { raw = '[!EXAMPLE]', rendered = '󰉹 Example', highlight = 'RenderMarkdownHint' },
      quote = { raw = '[!QUOTE]', rendered = '󱆨 Quote', highlight = 'RenderMarkdownQuote' },
    },
    link = {
      -- Turn on / off inline link icon rendering
      enabled = true,
      -- Inlined with 'image' elements
      image = '󰥶 ',
      -- Inlined with 'inline_link' elements
      hyperlink = '󰌹 ',
      -- Applies to the inlined icon
      highlight = 'RenderMarkdownLink',
    },
    sign = {
      -- Turn on / off sign rendering
      enabled = true,
      -- More granular mechanism, disable signs within specific buftypes
      exclude = {
        buftypes = { 'nofile' },
      },
      -- Applies to background of sign text
      highlight = 'RenderMarkdownSign',
    },
  },
  name = 'render-markdown', -- Only needed if you have another plugin named markdown.nvim
  dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.nvim' }, -- if you use the mini.nvim suite
  -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'echasnovski/mini.icons' }, -- if you use standalone mini plugins
  -- dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' }, -- if you prefer nvim-web-devicons
}
