return {
    "OXY2DEV/markview.nvim",
    lazy = false,
    config = function()
        require("markview").setup({
            markdown = {
                headings = {
                    heading_1 = { icon_hl = "@markup.link", icon = "[%d] " },
                    heading_2 = { icon_hl = "@markup.link", icon = "[%d.%d] " },
                    heading_3 = { icon_hl = "@markup.link", icon = "[%d.%d.%d] " }
                }
            }
        });

        -- **Preset** usage ------------------------------------------------------

        local presets = require("markview.presets").headings;

        require("markview").setup({
            markdown = { headings = presets.glow }
        });

        -- **Advanced** usage ----------------------------------------------------

        --- Gets icon from a parsed heading item.
        ---@param item markview.parsed.markdown.atx
        ---@return string
        local function get_icon(_, item)
            if not item or not item.levels then
                return "";
            end

            local output = "◈ ";

            for l, level in ipairs(item.levels) do
                if level ~= 0 then
                    output = output .. level .. (l ~= #item.levels and "." or "");
                end
            end

            return output .. " ";
        end
    end
};
