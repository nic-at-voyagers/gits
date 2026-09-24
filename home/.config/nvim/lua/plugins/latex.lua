return {
	{
		"kaarmu/typst.vim",
		ft = "typst",
	},
	{
		"al-kot/typst-preview.nvim",
		config = function()
			require("typst-preview").setup({ follow_cursor = false })
		end,
	}
}
