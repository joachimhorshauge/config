-- Treesitter.
--
-- Neovim ships the parsing engine and seven parsers (c, lua, markdown,
-- markdown_inline, query, vim, vimdoc) but no way to add an eighth: the runtime
-- has no parser installer. The tree-sitter-* packages in the Arch repos are not
-- that either — they exist to satisfy neovim's own dependencies, and the
-- queries they ship land in /usr/share/tree-sitter/queries, which is not on
-- 'runtimepath', written against capture names (@conditional, @parameter,
-- @field) that neovim replaced in 2023.
--
-- So this is here for the queries as much as for the parsers: nvim-treesitter
-- is what maintains highlights/indents/injections against the capture names
-- neovim actually uses.
--
-- Building a parser needs tree-sitter-cli (pacman -S tree-sitter-cli, 0.26.1 or
-- newer) and a C compiler. The plugin does not support lazy-loading.

local ts = require("nvim-treesitter")

ts.setup()

-- The seven neovim already bundles are left out: installing them again only
-- shadows the packaged ones, which are the versions its own queries were
-- written against.
local ensure = {
	"html",
	"css",
	-- The parser for the {{ }} actions. It is not attached to any filetype —
	-- template files are 'html' — but after/queries/html/injections.scm injects
	-- it into the HTML text, so it has to be installed for that to resolve.
	"gotmpl",
	"javascript", -- <script> blocks in templates, via html's own injections
	"typst",
	"go",
	"haskell",
	"gomod",
	"gosum",
	"gowork",
	"qmljs",
	"bash",
	"json",
	"yaml",
	"toml",
	"diff",
	"gitcommit",
}

-- Only the missing ones, so a normal startup does no work. install() is async;
-- it reports progress and the parsers become usable as they land.
local installed = {}
for _, lang in ipairs(ts.get_installed()) do
	installed[lang] = true
end

local missing = vim.tbl_filter(function(lang)
	return not installed[lang]
end, ensure)

if #missing > 0 then
	if vim.fn.executable("tree-sitter") == 0 then
		vim.notify(
			("treesitter: %d parsers to build, but tree-sitter-cli is not on PATH"):format(#missing),
			vim.log.levels.WARN
		)
	else
		ts.install(missing)
	end
end

-- Treesitter indent is opt-in per language. Neovim ships an indent file for
-- most of what is installed above — indent/go.vim, indent/qml.vim,
-- indent/json.vim — and those are long-settled; swapping them out wholesale
-- would be a lot of churn to buy nothing. typst is the one worth taking, its
-- runtime indent being the thin part of an otherwise good ftplugin.
local ts_indent = {
	typst = true,
}

-- Highlighting is not on by default for any filetype, not even the parsers
-- neovim bundles, so it has to be started per buffer. Anything without a parser
-- falls through to the runtime syntax file as before.
vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("Treesitter", { clear = true }),
	callback = function(args)
		local lang = vim.treesitter.language.get_lang(args.match) or args.match

		-- pcall because "no parser" is the common case here, not an error worth
		-- reporting: it is every filetype nothing was installed for.
		if not pcall(vim.treesitter.start, args.buf, lang) then
			return
		end

		if ts_indent[lang] and vim.treesitter.query.get(lang, "indents") then
			vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		end
	end,
})

-- Folding is left at its default. To fold by syntax instead, per window:
--   vim.wo[0][0].foldmethod = 'expr'
--   vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
--
-- The plugin brings :TSInstall, :TSUpdate, :TSUninstall and :TSLog with it, so
-- adding a parser by hand does not mean editing the list above.
