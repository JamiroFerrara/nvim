local ls = require("luasnip")
local s = ls.s
local i = ls.i
local t = ls.t

local d = ls.dynamic_node
local c = ls.choice_node
local f = ls.function_node
local sn = ls.snippet_node
local isn = ls.indent_snippet_node
local f = ls.function_node

local fmt = require("luasnip.extras.fmt").fmt
local rep = require("luasnip.extras").rep

local snippets, autosnippets = {}, {}

local group = vim.api.nvim_create_augroup("Lua Snippets", { clear = true })
local file_pattern = "*.cs"

local same = function(index)
        return f(function(arg)
                return arg[1] or ""
        end, { index })
end


local function split(pString, pPattern)
        local Table = {} -- NOTE: use {n = 0} in Lua-5.0
        local fpat = "(.-)" .. pPattern
        local last_end = 1
        local s, e, cap = pString:find(fpat, 1)
        while s do
                if s ~= 1 or cap ~= "" then
                        table.insert(Table, cap)
                end
                last_end = e + 1
                s, e, cap = pString:find(fpat, last_end)
        end
        if last_end <= #pString then
                cap = pString:sub(last_end)
                table.insert(Table, cap)
        end
        return Table
end

local this_init = function(index)
        return f(function(arg)
                local str = arg[1][1] or ""
                local tbl = split(str, ",")
                local ret = {}
                for key, value in pairs(tbl) do
                        local word = split(value, " ")[2] or "";
                        table.insert(ret, "this." .. word .. " = " .. word .. ";")
                end
                return ret
        end, { index })
end

local comma_getset = function(index)
        return f(function(arg)
                local str = arg[1][1] or ""
                return (str:gsub(",", " {get; set;}"))
        end, { index })
end

local get_file_name = function()
        return vim.fn.expand("%:t:r")
end

local ret =
s("ret", {
        t("return "), i(1)
})
table.insert(autosnippets, ret)

local tolist =
s("toli", {
        t("ToList();")
})
table.insert(autosnippets, tolist)

local tostr =
s("tostr", {
        t("ToString();")
})
table.insert(autosnippets, tostr)

local func =
s("func", {
        c(2, { t("public "), t("private ") }),
        i(3, "void"), t(" "), i(1), t("() "),
        t({ "", "{", }),
        i(0),
        t({ "", "}", }),
})
table.insert(autosnippets, func)

local ccln =
s("ccln", {
        t("namespace "), i(1),
        t({ "", "{", "", }),
        sn(2, { t("    "), t("public class "), f(get_file_name),
                t({ "", "    {", "        ", }),
                comma_getset(1),
                t({ "", "", "        public " }), f(get_file_name), t({ "(", }), i(1), t({ ")", "" }),
                t({ "        {", "", }),
                this_init(1),
                t({ "", "        }" }),
                t({ "", "    }", }),
        }),
        t({ "", "}", }),
})
table.insert(snippets, ccln)

local is_post = function(index)
        return f(function(arg)
                local value = arg[1][1] or ""
                if value == "[HttpPost(\"" then
                        return "[FromBody] "
                end
                if value == "[HttpGet(\"" then
                        return ""
                end
        end, { index })
end

local httpget =
s("hg", {
        c(2, { t("[HttpGet(\""), t("[HttpPost(\"") }), i(1), t("\")]"),
        t({ "", "public async Task<IActionResult> " }), same(1), t("("), is_post(2), i(3), t(")"),
        t({ "", "{" }),
        t({ "", "    return Ok();" }),
        t({ "", "}" })
})
table.insert(snippets, httpget)

local try =
s("try", {
        t({ "try", "" }),
        t({ "{", "" }),
        f(function()
                local yanked = split(vim.fn.getreg('1'), "\n")
                return yanked
        end),
        t({ "", "" }),
        t({ "}", "" }),
        t({ "catch (Exception ex)", "" }),
        t({ "{", "" }),
        t({ "", "" }),
        t({ "}" }),
})
table.insert(snippets, try)

return snippets, autosnippets
