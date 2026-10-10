vim.g.mapleader = " "

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })
vim.keymap.set("n", "J", "mzJ`z", { desc = "Join lines without moving the cursor" })
vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory" })
vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line Diagnostics" })

-- Neovim shows diagnostics only as signs and underlines by default. This writes
-- every message out in full beneath its line, for when the float is one line at
-- a time too slow.
vim.keymap.set("n", "<leader>cD", function()
	local on = not vim.diagnostic.config().virtual_lines
	vim.diagnostic.config({ virtual_lines = on })
	vim.notify("Diagnostic lines " .. (on and "on" or "off"))
end, { desc = "Toggle all diagnostics" })

-- Esc clears the search highlight as well as leaving whatever mode you are in.
vim.keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
