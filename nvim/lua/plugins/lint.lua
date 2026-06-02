local lint = require("lint")

lint.linters_by_ft = {
	go = { "golangcilint" },
}

-- Trigger lint on the events that matter. BufWritePost catches save,
-- BufReadPost catches first-open, InsertLeave catches edits.
local lint_group = vim.api.nvim_create_augroup("NvimLint", { clear = true })
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
	group = lint_group,
	callback = function()
		-- Only lint files on disk (skip [No Name], terminal buffers, etc.)
		if vim.bo.buftype == "" and vim.fn.filereadable(vim.api.nvim_buf_get_name(0)) == 1 then
			lint.try_lint()
		end
	end,
})
