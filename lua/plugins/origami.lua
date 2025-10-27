-- lazy.nvim
return {
	"chrisgrieser/nvim-origami",
	event = "VeryLazy",
	opts = {
	-- features incompatible with `nvim-ufo`
	-- useLspFoldsWithTreesitterFallback = not package.loaded["ufo"],
	-- autoFold = {
	-- 	enabled = false,
	-- 	kinds = { "comment", "imports" }, ---@type lsp.FoldingRangeKind[]
	-- },
	foldtext = {
		enabled = true,
		lineCount = {
			template = " ", -- `%d` gets the number of folded lines
			hlgroup = "Comment",
		},
		diagnostics = {
			enabled = true,
			-- uses hlgroups and icons from `vim.diagnostic.config().signs`
		},
	},
	--
	-- -- can be used with or without `nvim-ufo`
	-- pauseFoldsOnSearch = true,
	-- foldKeymaps = {
	-- 	setup = true, -- modifies `h` and `l`
	-- 	hOnlyOpensOnFirstColumn = false,
	-- },
	--
	-- -- feature requiring `nvim-ufo`
	-- keepFoldsAcrossSessions = package.loaded["ufo"],
}, -- needed even when using default config

	-- recommended: disable vim's auto-folding
	init = function()
		vim.opt.foldlevel = 99
		vim.opt.foldlevelstart = 99
	end,
}
