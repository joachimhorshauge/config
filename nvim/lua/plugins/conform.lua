require("conform").setup({
	formatters_by_ft = {
		go = { "goimports", "gofumpt" }, -- runs sequentially: imports first, then gofumpt
		lua = { "stylua" },
		qml = { "qmlformat" },

		-- djlint rather than prettier, and this is the whole reason: prettier
		-- parses HTML as HTML, so `{{ if }}<tr>{{ end }}` is an unclosed tag to
		-- it and it reflows the block into something that no longer compiles.
		-- djlint has a Go template profile and treats the actions as structure.
		html = { "djlint" },

		-- prettier is fine for real CSS — no template syntax reaches these
		-- files, and it is better at CSS than djlint is.
		css = { "prettier" },
		scss = { "prettier" },

		-- typst is absent on purpose: tinymist formats it with the typstyle it
		-- has built in, and `lsp_format = "fallback"` below reaches for the
		-- server precisely when no formatter is listed here.

		-- haskell and cabal are absent for the same reason: HLS has ormolu
		-- compiled in and formats through the LSP fallback, so there is no second
		-- binary to install and no chance of the two disagreeing about a file.
		-- The provider is named in lsp/hls.lua; switching it there is the whole
		-- change. A standalone ormolu listed here would take over instead, which
		-- is worth doing only to format Haskell in projects HLS refuses to load.
	},

	formatters = {
		djlint = {
			-- Reading from stdin means djlint never sees a filename, so it
			-- cannot guess the flavour — without --profile it falls back to the
			-- plain-HTML rules and mangles {{ }} exactly like prettier would.
			--
			-- --indent matches 'shiftwidth'; djlint emits spaces either way,
			-- there being no tab mode.
			prepend_args = { "--profile=golang", "--indent=4" },
		},
	},

	-- Format on save. Returns nil to skip, or a table of format opts.
	format_on_save = function(bufnr)
		-- Allow opting out per buffer or globally.
		if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
			return nil
		end
		return { timeout_ms = 2000, lsp_format = "fallback" }
	end,

	-- Quieter notifications; conform still logs to :ConformInfo.
	notify_on_error = false,
})

-- Toggle commands — handy when you want to save without reformatting.
vim.api.nvim_create_user_command("FormatDisable", function(args)
	if args.bang then
		vim.b.disable_autoformat = true
	else
		vim.g.disable_autoformat = true
	end
end, { desc = "Disable autoformat-on-save (use ! for buffer-only)", bang = true })

vim.api.nvim_create_user_command("FormatEnable", function()
	vim.b.disable_autoformat = false
	vim.g.disable_autoformat = false
end, { desc = "Re-enable autoformat-on-save" })
