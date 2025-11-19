vim.api.nvim_create_autocmd('BufEnter', {
  pattern = '*.cs',
  nested = true,
  callback = function()
    vim.cmd 'hi @type.builtin guifg=#89b4fa'
    vim.cmd 'hi @parameter guifg=#cdd6f4'
    vim.cmd 'hi @field guifg=#cdd6f4'
    vim.cmd 'hi @function guifg=#b4befe'
    vim.cmd 'hi @method guifg=#b4befe'
    vim.cmd 'hi @keyword guifg=#cba6f7'
    vim.cmd 'hi @method.call guifg=#89b4fa'
  end,
})

vim.api.nvim_create_autocmd('BufEnter', {
  desc = 'On buffer enter set highlights',
  group = vim.api.nvim_create_augroup('kickstart-harpoon-nav', { clear = true }),
  callback = function()
    vim.cmd 'highlight LineNrAbove guifg=#6e7396'
    vim.cmd 'highlight LineNrBelow guifg=#6e7396'
    vim.cmd 'highlight LineNr guifg=#b4befe'

    vim.cmd 'highlight @markup.quote guifg=@text'

    -- Markdown
    vim.cmd 'highlight @markup.heading.1.markdown gui=bold guifg=#89b4fa guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @markup.heading.2.markdown gui=bold guifg=#f5a97f guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @markup.heading.3.markdown gui=bold guifg=#a6da95 guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @markup.heading.4.markdown gui=bold guifg=#eed49f guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @markup.heading.5.markdown gui=bold guifg=#8aadf4 guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @markup.heading.6.markdown gui=bold guifg=#ed8796 guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'

    -- Org
    vim.cmd 'highlight @org.headline.level1 gui=bold guifg=#89b4fa guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @org.headline.level2 gui=bold guifg=#f5a97f guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @org.headline.level3 gui=bold guifg=#a6da95 guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @org.headline.level4 gui=bold guifg=#eed49f guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @org.headline.level5 gui=bold guifg=#8aadf4 guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'

    vim.cmd 'highlight @org.priority.high gui=bold guifg=#000000 guibg=#8aadf4'
    vim.cmd 'highlight @org.priority.default gui=bold guifg=#000000 guibg=#89b4fa'
    vim.cmd 'highlight @org.priority.low gui=bold guifg=#000000 guibg=#eed49f'
    vim.cmd 'highlight @org.priority.lowest gui=bold guifg=#000000 guibg=#eed49f'

    vim.cmd 'highlight link RenderMarkdownDash Comment'

    vim.cmd 'highlight @markup.link.label guifg=#c6a0f6' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight @markup.raw.block guibg=#292f45' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'

    vim.cmd 'highlight RenderMarkdownCode guibg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
    vim.cmd 'highlight mkdCodeDelimiter guibg=none guifg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'

    vim.cmd 'highlight Folded guibg=none guifg=none' -- vim.cmd 'highlight @markup.heading.3.markdown guifg=@text'
  end,
})

