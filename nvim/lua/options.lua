-- ============================================================================
-- Netrw (built-in file explorer)
-- ============================================================================
vim.g.netrw_banner = 0
vim.g.netrw_winsize = 30

-- ============================================================================
-- Line numbers
-- ============================================================================
vim.opt.number = true
vim.opt.relativenumber = true

-- ============================================================================
-- Search
-- ============================================================================
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.inccommand = "split"  -- live preview of :substitute

-- ============================================================================
-- Indentation
-- ============================================================================
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = false     -- use real tabs, not spaces
vim.opt.breakindent = true    -- wrapped lines keep visual indent

-- ============================================================================
-- Display
-- ============================================================================
vim.opt.wrap = false
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.colorcolumn = "0"
vim.opt.laststatus = 3        -- global statusline
vim.o.cmdheight = 0           -- hide cmdline when not in use
vim.opt.guicursor = ""        -- use terminal's cursor shapei
vim.opt.termguicolors = true

-- ============================================================================
-- Splits
-- ============================================================================
vim.opt.splitbelow = true
vim.opt.splitright = true

-- ============================================================================
-- Files & undo
-- ============================================================================
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undodir = vim.fn.stdpath("data") .. "/undodir"
vim.opt.undofile = true       -- persistent undo across sessions
vim.opt.isfname:append("@-@")

-- ============================================================================
-- Clipboard
-- ============================================================================
-- Sync unnamed register with system clipboard so y/p work with the OS.
-- Use "unnamed" for the * register (X11 primary / selection) or
-- "unnamedplus" for the + register (system clipboard); both is common.
vim.opt.clipboard = "unnamedplus"

-- ============================================================================
-- Autocommands
-- ============================================================================
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking text",
	callback = function()
		vim.hl.on_yank()
	end,
})
