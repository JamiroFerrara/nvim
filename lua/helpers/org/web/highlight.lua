-- Treesitter highlighting for the source blocks of the browser views
-- (helpers/org/web). org.nvim's HTML export colours a block with Emacs'
-- htmlize, which knows one fixed set of languages and one stab at the
-- colours; the browser views should read like the buffer instead, whatever
-- language the block is written in (lua, typescript, markdown, org, sql...).
--
-- The block's text is parsed with nvim's own treesitter parser and the
-- `highlights` query, the way the editor highlights it, and every capture is
-- resolved to the colour the active colorscheme gives its highlight group --
-- the same groups the TUI draws, so the page matches the editor (catppuccin
-- here). Overlapping captures paint in query order, the innermost last, so a
-- `@keyword` inside a markdown heading keeps its own colour.
--
-- A language with no parser, or a block too long to be worth the work, is
-- left to the exporter's own rendering.
local M = {}

-- filetype/alias -> treesitter language. Org users write what they mean
-- (`sh`, `c#`, `ts`, `console`), not the parser's name.
local ALIASES = {
  bash = 'bash',
  sh = 'bash',
  shell = 'bash',
  zsh = 'bash',
  console = 'bash',
  c = 'c',
  cpp = 'cpp',
  ['c++'] = 'cpp',
  cs = 'c_sharp',
  csharp = 'c_sharp',
  c_sharp = 'c_sharp',
  ['c#'] = 'c_sharp',
  css = 'css',
  csv = 'csv',
  diff = 'diff',
  dockerfile = 'dockerfile',
  editorconfig = 'editorconfig',
  elisp = 'lua',
  go = 'go',
  html = 'html',
  http = 'http',
  javascript = 'javascript',
  js = 'javascript',
  jsx = 'javascript',
  json = 'json',
  jsonc = 'jsonc',
  lua = 'lua',
  make = 'make',
  makefile = 'make',
  markdown = 'markdown',
  md = 'markdown',
  org = 'org',
  php = 'php',
  powershell = 'powershell',
  ps1 = 'powershell',
  python = 'python',
  py = 'python',
  sql = 'sql',
  tmux = 'tmux',
  toml = 'toml',
  tsx = 'tsx',
  tsv = 'tsv',
  typescript = 'typescript',
  ts = 'typescript',
  vim = 'vim',
  xml = 'xml',
  yaml = 'yaml',
  yml = 'yaml',
}

local MAX_BYTES = 200 * 1024
local MAX_DEPTH = 3
local cache = {}
local runtime_loaded = false

--- Make nvim-treesitter's runtime (its query files, the parsers' grammars
--- beyond the ones nvim ships) reachable before the first query lookup:
--- `vim.treesitter.query.get` caches a miss, so asking too early would keep
--- `bash` unhighlighted for the whole session.
local function ensure_queries()
  if runtime_loaded then
    return
  end
  runtime_loaded = true
  if not vim.o.runtimepath:find 'nvim%-treesitter' then
    pcall(require, 'nvim-treesitter')
  end
end

--- The colour table of a highlight group: fills `fg`, `bg`, `bold`,
--- `italic`, `underline` and `strikethrough`.
---@param name string
---@return table|nil
local function group_attrs(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if not ok or type(hl) ~= 'table' then
    return nil
  end
  local cterm = hl.cterm or {}
  local any = hl.fg or hl.bg or hl.bold or hl.italic or hl.underline or hl.strikethrough or cterm.bold or cterm.italic or cterm.underline
  if not any then
    return nil
  end
  return {
    fg = hl.fg,
    bg = hl.bg,
    bold = hl.bold or cterm.bold or false,
    italic = hl.italic or cterm.italic or false,
    underline = hl.underline or cterm.underline or false,
    strikethrough = hl.strikethrough or cterm.strikethrough or false,
  }
end

--- `@function.builtin` -> the attributes of `@function.builtin` when the
--- colorscheme defines it, else its nearest defined parent (`@function`,
--- then `@…`). This is how nvim's highlighter falls back too.
---@param capture string
---@return table|nil
local function capture_attrs(capture)
  local name = '@' .. capture
  while true do
    local attrs = group_attrs(name)
    if attrs then
      return attrs
    end
    local trimmed = name:gsub('%.%w+$', '')
    if trimmed == name or trimmed == '@' then
      return nil
    end
    name = trimmed
  end
end

---@param n number|nil
---@return string|nil
local function hex(n)
  if type(n) ~= 'number' or n < 0 then
    return nil
  end
  return ('#%06x'):format(n)
end

--- The inline style for one byte of text, or nil when the text keeps the
--- block's own colour.
---@param attrs table|nil
---@param default_bg number|nil
---@return string|nil
local function style_of(attrs, default_bg)
  if not attrs then
    return nil
  end
  local parts = {}
  local fg = hex(attrs.fg)
  if fg then
    parts[#parts + 1] = 'color:' .. fg
  end
  local bg = hex(attrs.bg)
  if bg and bg ~= default_bg then
    parts[#parts + 1] = 'background:' .. bg
  end
  if attrs.bold then
    parts[#parts + 1] = 'font-weight:700'
  end
  if attrs.italic then
    parts[#parts + 1] = 'font-style:italic'
  end
  local deco = {}
  if attrs.underline then
    deco[#deco + 1] = 'underline'
  end
  if attrs.strikethrough then
    deco[#deco + 1] = 'line-through'
  end
  if #deco > 0 then
    parts[#parts + 1] = 'text-decoration:' .. table.concat(deco, ' ')
  end
  return #parts > 0 and table.concat(parts, ';') or nil
end

--- Escape text for HTML.
---@param text string
---@return string
local function escape(text)
  return (text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

--- Byte offset of a (row, col) position in `code`.
---@param code string
---@param row integer
---@param col integer
---@return integer
local function offset(code, row, col)
  if row == 0 then
    return col
  end
  local pos = 0
  for _ = 1, row do
    local nl = code:find('\n', pos + 1, true)
    if not nl then
      return #code
    end
    pos = nl
  end
  return pos + col
end

--- Paint `code` (written in `lang`) into `styles`, at `base` bytes into
--- the block. A language injection -- markdown's inline markup, a fenced
--- block inside a markdown block -- is parsed on its own and painted over
--- the same bytes, so the inner language wins where they overlap.
---@param lang string
---@param code string
---@param base integer
---@param styles table<integer, string>
---@param ctx { bg: string|nil, attrs: table<string, table|false>, depth: integer }
local function paint(lang, code, base, styles, ctx)
  if code == '' or ctx.depth > MAX_DEPTH then
    return
  end
  local ok, parser = pcall(vim.treesitter.get_string_parser, code, lang)
  if not ok or not parser then
    return
  end
  local pok, tree = pcall(function()
    return parser:parse()[1]
  end)
  if not pok or not tree then
    return
  end
  local root = tree:root()
  local query = vim.treesitter.query.get(lang, 'highlights')
  if query then
    pcall(function()
      for id, node in query:iter_captures(root, code, 0, -1) do
        local capture = query.captures[id]
        -- the spell captures only drive nvim's own spell UI
        if capture and capture:sub(1, 5) ~= 'spell' then
          local attrs = ctx.attrs[capture]
          if attrs == nil then
            attrs = capture_attrs(capture) or false
            ctx.attrs[capture] = attrs
          end
          local style = attrs and style_of(attrs, ctx.bg)
          if style then
            local sr, sc, er, ec = node:range()
            local from = base + offset(code, sr, sc)
            local to = base + offset(code, er, ec)
            for i = from, to - 1 do
              styles[i] = style
            end
          end
        end
      end
    end)
  end
  local injections = vim.treesitter.query.get(lang, 'injections')
  if not injections then
    return
  end
  pcall(function()
    for _, match, metadata in injections:iter_matches(root, code, 0, -1, { all = true }) do
      local contents
      local injected = metadata and metadata['injection.language']
      for id, nodes in pairs(match) do
        local name = injections.captures[id]
        if name == 'injection.content' then
          contents = nodes
        elseif name == 'injection.language' then
          local text = nodes[1] and vim.treesitter.get_node_text(nodes[1], code)
          if text and text ~= '' then
            injected = text:lower()
          end
        end
      end
      if contents and injected then
        for _, node in ipairs(contents) do
          local sr, sc, er, ec = node:range()
          local from = offset(code, sr, sc)
          local to = offset(code, er, ec)
          if to > from then
            paint(ALIASES[injected] or injected, code:sub(from + 1, to), base + from, styles, {
              bg = ctx.bg,
              attrs = ctx.attrs,
              depth = ctx.depth + 1,
            })
          end
        end
      end
    end
  end)
end

--- Highlight `code` as `lang`, returning the inner HTML of a `<code>`
--- element, or nil when the language has no parser (the caller then keeps
--- the exporter's own rendering).
---@param code string
---@param lang string
---@return string|nil
function M.code(code, lang)
  if type(code) ~= 'string' or code == '' or #code > MAX_BYTES then
    return nil
  end
  local key = (lang or '') .. '\0' .. code
  local hit = cache[key]
  if hit ~= nil then
    return hit or nil
  end
  ensure_queries()
  local parser_lang = ALIASES[(lang or ''):lower()] or (lang or ''):lower()
  if parser_lang == '' then
    cache[key] = false
    return nil
  end
  local normal = group_attrs 'Normal'
  local styles = {} -- byte -> inline style
  local probe = pcall(function()
    return vim.treesitter.get_string_parser(code, parser_lang)
  end)
  if not probe then
    cache[key] = false
    return nil
  end
  paint(parser_lang, code, 0, styles, {
    bg = normal and hex(normal.bg) or nil,
    attrs = {},
    depth = 0,
  })

  local out = {}
  local i = 1
  while i <= #code do
    local style = styles[i - 1]
    local j = i
    while j < #code and styles[j] == style do
      j = j + 1
    end
    local text = escape(code:sub(i, j))
    if style then
      out[#out + 1] = '<span style="' .. style .. '">' .. text .. '</span>'
    else
      out[#out + 1] = text
    end
    i = j + 1
  end
  local html = table.concat(out)
  cache[key] = html
  return html
end

--- Decode the entities the exporter writes into a block's text.
---@param text string
---@return string
local function unescape(text)
  local named = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'" }
  text = text:gsub('&#[xX](%x+);', function(code)
    return string.char(tonumber(code, 16) % 256)
  end)
  text = text:gsub('&#(%d+);', function(code)
    return string.char(tonumber(code) % 256)
  end)
  return (text:gsub('&(%a+);', function(name)
    return named[name] or ('&' .. name .. ';')
  end))
end

--- A source block drawn as a snippet: a title bar with the language -- and the
--- file the block came from, when it names one -- and a button that copies the
--- code, over the coloured block. The button finds the text in the <pre> it
--- sits above (app.js, page.lua), so the markup carries one copy of it.
---@param lang string
---@param inner string the block's inner HTML, already escaped/coloured
---@param ref? { label: string, href: string, title: string } the file the block names
---@return string
function M.snippet(lang, inner, ref)
  lang = (lang or ''):gsub('^%s+', ''):gsub('%s+$', '')
  local name = lang ~= '' and escape(lang) or 'code'
  local file = ''
  if ref and ref.label then
    file = ('<span class="snippet-arrow">→</span><a href="%s" class="snippet-file" title="%s">%s</a>'):format(
      escape(ref.href),
      escape(ref.title or ref.href),
      escape(ref.label)
    )
  end
  return (
    '<figure class="snippet"><div class="snippet-bar"><span class="snippet-lang">%s</span>%s'
    .. '<button class="snippet-copy" type="button" title="Copy this snippet">copy</button></div>'
    .. '<pre class="src src-%s"><code>%s</code></pre></figure>'
  ):format(name, file, name, inner)
end

--- Replace every source block of an exported org document with the
--- treesitter rendering of its code, inside the snippet frame. A markdown
--- block is laid out as the markdown it holds (helpers/org/web/markdown),
--- its fenced blocks becoming snippets of their own; a block whose language
--- has no parser keeps the exporter's own colouring.
---@param html string|nil
---@return string|nil
function M.html(html)
  if type(html) ~= 'string' or html == '' then
    return html
  end
  return (
    html:gsub('<pre class="src src%-([%w%+%#%._%-]+)">%s*<code>(.-)</code>%s*</pre>', function(lang, inner)
      -- the exporter has already coloured the block with htmlize: take its
      -- text back out of its spans and let treesitter colour it instead
      local code = unescape((inner:gsub('<[^>]*>', '')))
      local key = lang:lower()
      if key == 'markdown' or key == 'md' then
        return require('helpers.org.web.markdown').render(code)
      end
      return M.snippet(lang, M.code(code, lang) or inner)
    end)
  )
end

--- Clear the highlight cache (the colorscheme may have changed).
function M.clear()
  cache = {}
end

return M
