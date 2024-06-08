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
local file_pattern = "*.*"

local date =
s("date", {
  f(function()
    return os.date "%D - %H:%M"
  end)
})
table.insert(snippets, date)

local time =
s("time", {
  f(function()
    return os.date "%H:%M"
  end)
})
table.insert(snippets, time)

return snippets, autosnippets
