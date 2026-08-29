-- Filetype detection for Go's html/template files.
--
-- Neovim 0.12 maps '*.tmpl' to the 'template' filetype — a generic text ft with
-- no syntax, no ftplugin and nothing that would attach an HTML server — and does
-- not recognise '*.gohtml' or '*.gotmpl' at all, leaving those buffers with no
-- filetype whatsoever.
--
-- All three are HTML here, so all three are called HTML. That is what puts the
-- html server, emmet, treesitter and djlint on them; the {{ }} actions ride
-- along inside as text, which every one of those tolerates.
vim.filetype.add({
	extension = {
		tmpl = 'html',
		gotmpl = 'html',
		gohtml = 'html',
	},
})

-- Which HTML buffers are Go templates, as opposed to plain markup that happens
-- to be open. Anything under a Go module is; the extensions above are,
-- wherever they live.
--
-- Only go-template-lsp reads this — the html server and djlint are happy to
-- treat every HTML buffer the same way — but it is the honest place to answer
-- the question once.
local template_ext = { tmpl = true, gotmpl = true, gohtml = true }

local function is_go_template(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == '' then
		return false
	end

	if template_ext[vim.fn.fnamemodify(name, ':e')] then
		return true
	end

	return #vim.fs.find({ 'go.mod' }, { upward = true, path = vim.fs.dirname(name) }) > 0
end

vim.api.nvim_create_autocmd('FileType', {
	group = vim.api.nvim_create_augroup('GoTemplateFiletype', { clear = true }),
	pattern = 'html',
	callback = function(args)
		vim.b[args.buf].go_template = is_go_template(args.buf)
	end,
})
