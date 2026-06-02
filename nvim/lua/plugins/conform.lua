require("conform").setup({
	formatters_by_ft = {
		go = { "goimports", "gofumpt" }, -- runs sequentially: imports first, then gofumpt
		lua = { "stylua" },
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
