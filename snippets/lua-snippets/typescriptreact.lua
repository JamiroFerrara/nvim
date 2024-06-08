local ls = require("luasnip")
local s = ls.s
local i = ls.i
local t = ls.t

local d = ls.dynamic_node
local c = ls.choice_node
local f = ls.function_node
local sn = ls.snippet_node

local fmt = require("luasnip.extras.fmt").fmt
local rep = require("luasnip.extras").rep

local snippets, autosnippets = {}, {}

local group = vim.api.nvim_create_augroup("Lua Snippets", { clear = true })
local file_pattern = "*.tsx"

local same = function(index)
        return f(function(arg)
                return arg[1] or ""
        end, { index })
end

local same_upper = function(index)
        return f(function(arg)
                local str = arg[1][1] or ""
                return (str:gsub("^%l", string.upper))
        end, { index })
end

local useState =
s("useState", fmt([[const [{}, set{}] = useState{}({}); ]], { i(1), same_upper(1), i(3), i(2) }))
table.insert(snippets, useState)

local useEffect =
s("useEffect", fmt([[
useEffect(() => {{
        {}
}}{}]], { i(0), c(1, { sn(nil, { t(", ["), i(1), t("]);") }), t("") })
}))
table.insert(snippets, useEffect)

return snippets, autosnippets
