return {
	{ "folke/tokyonight.nvim",
		opts = {
			transparent = true,
			terminal_colors = true,
			styles = {
				conditionals = {"italic"},
				sidebars = "transparent",
				floats = "transparent",
			}
		}
	},

	{ "catppuccin/nvim",
		opts = {
			transparent_background = true,
			term_colors = true,
			float = {
				transparent = true,
			},
			color_overrides = {
				all = {
					base = "#11111b",
					mantle = "#11111b",
					blue = "#89b4fa",
					yellow = "#f5d180",
					mauve = "#c5aaf8",
					teal = "#74c7ec"
				}
			},
			custom_highlights = function(colors)
				return {
					CursorLineNr = { fg = colors.sky},
					["@property"] = {fg = colors.mauve},
					ColorColumn = {fg = "#0e1022"},
				}
			end

		}
	},

	{ "LazyVim/LazyVim",
		opts = {
			colorscheme = "catppuccin-mocha",
		}
	}
}
