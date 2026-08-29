local lint = require("lint")

lint.linters_by_ft = {
	go = { "golangcilint" },

	-- Only reached when HLS is not attached — see the gate below. Wanting it
	-- means `pacman -S hlint`; with only haskell-language-server installed
	-- this entry never runs, and nothing is missing when it doesn't.
	haskell = { "hlint" },
}

-- Trigger lint on the events that matter. BufWritePost catches save,
-- BufReadPost catches first-open, InsertLeave catches edits.
local lint_group = vim.api.nvim_create_augroup("NvimLint", { clear = true })
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
	group = lint_group,
	callback = function()
		-- Only lint files on disk (skip [No Name], terminal buffers, etc.)
		if vim.bo.buftype ~= "" or vim.fn.filereadable(vim.api.nvim_buf_get_name(0)) ~= 1 then
			return
		end

		-- HLS compiles hlint in as a plugin, so a Haskell buffer with the
		-- server attached is already publishing these exact warnings — and one
		-- better, since each carries an "Apply hint" code action that the
		-- standalone binary has no way to offer. Running nvim-lint on top would
		-- print every suggestion twice, in two namespaces, one of them unfixable.
		--
		-- The gate is on the client rather than on the filetype because the
		-- case it exists for is real: HLS declines a buffer whose GHC it cannot
		-- match, and a file left with no server should still get linted.
		if vim.bo.filetype == "haskell" and #vim.lsp.get_clients({ bufnr = 0, name = "hls" }) > 0 then
			return
		end

		lint.try_lint()
	end,
})
