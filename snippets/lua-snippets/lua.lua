local ls = require("luasnip")
local s = ls.s
local i = ls.i
local t = ls.t

local d = ls.dynamic_node
local c = ls.choice_node
local f = ls.function_node
local sn = ls.snippet_node
local f = ls.function_node

local fmt = require("luasnip.extras.fmt").fmt
local rep = require("luasnip.extras").rep

local snippets, autosnippets = {}, {}

local group = vim.api.nvim_create_augroup("Lua Snippets", { clear = true })
local file_pattern = "*.lua"

------------------------------
--EXAMPLES
------------------------------

--INSERT EXAMPLE
local insertSnippet =
s("insertSnippet", {
  t("Hi! This is my first luasnip "),
  i(1, "first"),
  t(" : "),
  i(2, "second"),
})
table.insert(snippets, insertSnippet)

--FUNCTION EXAMPLE
local function fn(
  args, -- text from i(2) in this example i.e. { { "456" } }
  parent, -- parent snippet or parent node
  user_args -- user_args from opts.user_args
)
  return '[' .. args[1][1] .. user_args .. ']'
end

local functionSnippet =
s("functionSnippet", {
  i(1), t '<-i(1) ',
  f(fn, -- callback (args, parent, user_args) -> string
    { 2 }, -- node indice(s) whose text is passed to fn, i.e. i(2)
    { user_args = { "user_args_value" } }-- opts
  ),
  t ' i(2)->', i(2), t '<-i(2) i(0)->', i(0)
})
table.insert(snippets, functionSnippet)

--CHOICE SNIPPET
local choiceSnippet =
s("todo", c(1, {
  t("--TODO"),
  t("--FIXME"),
}))
table.insert(autosnippets, choiceSnippet)

return snippets, autosnippets
