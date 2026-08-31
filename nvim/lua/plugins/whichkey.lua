local wk = require("which-key")

wk.setup({
	-- Popup shows up a little quicker than the default 'timeoutlen'.
	delay = 300,
})

wk.add({
	{ "<leader>z", group = "zk", mode = { "n", "v" } },
	{ "<leader>f", group = "find" },
	{ "<leader>c", group = "code", mode = { "n", "v" } },
	{ "<leader>d", group = "draw" },
	{ "<leader>x", group = "exercise" },
})
