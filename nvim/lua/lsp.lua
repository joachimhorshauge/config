vim.lsp.enable('luals')
vim.lsp.enable('gopls')
vim.lsp.enable('qmlls')
vim.lsp.enable('tinymist')
vim.lsp.enable('hls')

-- Three servers share the HTML buffer: html answers for markup and the hx-*
-- custom data, emmet expands abbreviations, cssls takes the .css files and the
-- <style> blocks html hands off. Overlapping servers are normal LSP and blink
-- merges their completions.
vim.lsp.enable('html')
vim.lsp.enable('cssls')
vim.lsp.enable('emmet')

-- Neovim 0.12 maps the usual LSP actions itself when a client attaches:
--
--   K    hover          grn  rename          gri  implementation
--   grr  references     gra  code action     grt  type definition
--   gO   document symbol                     grx  run codelens
--
-- So only the ones it does not provide are set here. Mapping `gr` on top of
-- that family was the expensive mistake: every one of the six built-ins then
-- had to wait out 'timeoutlen' before it could fire.
vim.api.nvim_create_autocmd('LspAttach', {
	callback = function(args)
		local bufnr = args.buf
		local map = function(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
		end

		-- A wiki link is a notebook concept rather than a language one, and zk's
		-- server answers no definition on the `![[note]]` form, so a markdown
		-- buffer gets a look at the link first. Everything the notebook cannot
		-- resolve — including a link that names a note by title — falls through
		-- to the server unchanged.
		map('n', 'gd', function()
			if vim.bo[bufnr].filetype == 'markdown' and require('plugins.zk').follow_wiki_link() then
				return
			end
			vim.lsp.buf.definition()
		end, 'Go to definition')
		map('n', 'gD', vim.lsp.buf.declaration, 'Go to declaration')

		-- Under <leader>c with the rest of the code actions. It cannot live at
		-- <leader>f: that is the find prefix, and a mapping there stalls every
		-- telescope key behind it.
		map('n', '<leader>cf', function()
			vim.lsp.buf.format({ async = true })
		end, 'Format buffer')
	end,
})

-- go-template-lsp, on top of the html server rather than instead of it: it is
-- the only one of the three that reads the {{ }} actions, so it is what knows a
-- `{{ template "row" }}` names a block defined elsewhere and that `{{ end }}` is
-- missing.
--
-- It is not started here, because it does not work. Two things were wrong, and
-- only the first was this config's fault:
--
--   1. The autocmd hung off `pattern = "tmpl"`, so it had never once fired —
--      '*.tmpl' is the 'template' filetype in neovim 0.12, not 'tmpl'.
--
--   2. Fixing that revealed the real problem. go-template-lsp v0.4.1 answers
--      initialize twice, and pushes textDocument/publishDiagnostics before it
--      has answered at all. Neovim 0.12 rejects the second copy with
--      INVALID_SERVER_MESSAGE and shuts the client down, so it dies about a
--      second after every template buffer opens, having attached to nothing.
--
-- Nothing on this side fixes that. Treesitter covers the {{ }} highlighting
-- (after/queries/html/injections.scm) and djlint covers the formatting, which
-- was most of what it was here for. To try it again after an upstream release:
--
--   vim.api.nvim_create_autocmd("FileType", {
--     pattern = "html",
--     callback = function(args)
--       if not vim.b[args.buf].go_template then return end
--       local root = vim.fs.root(args.buf, { "go.mod", "go.work" })
--       if not root then return end
--       vim.lsp.start({
--         name = "go-template-lsp",
--         cmd = { "go-template-lsp" },
--         root_dir = root,
--       }, { bufnr = args.buf })
--     end,
--   })
