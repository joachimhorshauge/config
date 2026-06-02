vim.pack.add({
	{ src = "https://github.com/neanias/everforest-nvim" },
	{ src = "https://github.com/saghen/blink.cmp", version = vim.version.range("1.*") },
	{ src = "https://github.com/stevearc/oil.nvim"},
	{ src = "https://github.com/nvim-lua/plenary.nvim"},
	{ src = "https://github.com/nvim-telescope/telescope.nvim"},
	{ src = "https://github.com/folke/which-key.nvim"},
	{ src = "https://github.com/stevearc/conform.nvim" },
	{ src = "https://github.com/mfussenegger/nvim-lint" },
})

require("plugins.colorscheme")
require("plugins.completion")
require("plugins.oil")
require("plugins.telescope")
require("plugins.conform")
require("plugins.lint")
