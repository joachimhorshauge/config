vim.pack.add({
	{ src = "https://github.com/neanias/everforest-nvim" },
	{ src = "https://github.com/saghen/blink.cmp", version = vim.version.range("1.*") },
	{ src = "https://github.com/stevearc/oil.nvim"},
	{ src = "https://github.com/nvim-lua/plenary.nvim"},
	{ src = "https://github.com/nvim-telescope/telescope.nvim"},
	{ src = "https://github.com/folke/which-key.nvim"},
	{ src = "https://github.com/stevearc/conform.nvim" },
	{ src = "https://github.com/mfussenegger/nvim-lint" },
	{ src = "https://github.com/zk-org/zk-nvim" },
	-- Snippet bodies only — no runtime, no setup call. blink reads the
	-- VS Code-format snippets/package.json out of whatever is on 'runtimepath',
	-- which is what this package exists to put there.
	{ src = "https://github.com/rafamadriz/friendly-snippets" },
	-- 'main' is the rewrite, and the only branch that supports nvim 0.12; the
	-- default branch is still the old 'master' with the incompatible API.
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter", version = "main" },
})

require("plugins.colorscheme")
require("plugins.treesitter")
require("plugins.whichkey")
require("plugins.completion")
require("plugins.oil")
require("plugins.telescope")
require("plugins.conform")
require("plugins.lint")
require("plugins.zk")

-- Local config, not packages: the first drives the notes-site preview server,
-- the second drives tinymist's.
require("plugins.notes-site")
require("plugins.typst")
