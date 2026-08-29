-- Typst, driven through tinymist.
--
-- tinymist is both the language server and the preview server: the same
-- process that answers completion also renders the document and pushes frames
-- to a browser over a websocket. So there is no plugin here and nothing to
-- install beyond tinymist itself — previewing is an LSP `workspace/executeCommand`
-- against the client that is already attached to the buffer.
--
-- What that buys over `typst watch` + a PDF viewer is that the preview follows
-- the buffer as it is typed, with no file written to disk in between.

local M = {}

local state = {
	-- The address tinymist's static file server came up on, remembered so a
	-- second :TypstPreview reopens the tab instead of starting another server.
	addr = nil,
	-- What startDefaultPreview names the task it creates. Killing it needs the
	-- id back, and the server answers "task not found" for anything else —
	-- including 'primary', which is reserved for a different thing.
	task = "default_preview",
}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "typst" })
end

-- client returns the tinymist attached to the buffer, or nil with a reason.
-- Everything below goes through the server, so this is the one failure worth
-- reporting well: a missing binary and an unopened .typ file look identical
-- from the call site otherwise.
local function client(bufnr)
	local found = vim.lsp.get_clients({ bufnr = bufnr, name = "tinymist" })[1]
	if found then
		return found
	end
	if vim.fn.executable("tinymist") == 0 then
		return nil, "tinymist is not on PATH (pacman -S tinymist)"
	end
	return nil, "no tinymist attached to this buffer"
end

-- The file a command should act on. tinymist wants a plain absolute path here,
-- not a URI: hand it the `file://` form and it joins that onto the project root
-- and fails on the result.
local function current_path()
	return vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
end

-- exec runs one of tinymist's commands against the current buffer. The result
-- is handed to `on_result`; errors are reported rather than passed on, so
-- callers only deal with the success case.
local function exec(command, arguments, on_result)
	local bufnr = vim.api.nvim_get_current_buf()
	local found, err = client(bufnr)
	if not found then
		notify(err, vim.log.levels.ERROR)
		return
	end

	found:exec_cmd({ command = command, arguments = arguments }, { bufnr = bufnr }, function(cmd_err, result)
		if cmd_err then
			notify(command .. ": " .. (cmd_err.message or vim.inspect(cmd_err)), vim.log.levels.ERROR)
			return
		end
		if on_result then
			vim.schedule(function()
				on_result(result)
			end)
		end
	end)
end

-- ============================================================================
-- Preview
-- ============================================================================

function M.preview()
	if state.addr then
		vim.ui.open("http://" .. state.addr)
		return
	end

	exec("tinymist.startDefaultPreview", {}, function(result)
		-- The server reports where it bound. Reading the port back rather than
		-- fixing one in the config means two nvim instances can preview at once.
		local addr = result and (result.staticServerAddr or result.staticServerPort)
		if not addr then
			notify("preview started but reported no address:\n" .. vim.inspect(result), vim.log.levels.WARN)
			return
		end
		-- staticServerPort on its own is just a number; staticServerAddr is
		-- already host:port.
		if type(addr) == "number" then
			addr = "127.0.0.1:" .. addr
		end

		state.addr = addr
		vim.ui.open("http://" .. addr)
		notify("previewing at http://" .. addr)
	end)
end

function M.stop_preview()
	if not state.addr then
		notify("no preview running")
		return
	end
	exec("tinymist.doKillPreview", { state.task }, function()
		state.addr = nil
		notify("preview stopped")
	end)
end

function M.toggle_preview()
	if state.addr then
		M.stop_preview()
	else
		M.preview()
	end
end

-- ============================================================================
-- Export
-- ============================================================================

-- pdf writes the document out and opens it. This is the deliberate export;
-- `exportPdf = 'never'` in lsp/tinymist.lua means nothing else produces one.
function M.pdf()
	exec("tinymist.exportPdf", { current_path() }, function(result)
		-- The reply is { data, path }; only the path is of use, and it is
		-- absent when the document failed to compile.
		local path = type(result) == "table" and result.path
		if type(path) ~= "string" or path == "" then
			notify("export produced no file — does the document compile?", vim.log.levels.WARN)
			return
		end
		notify("wrote " .. vim.fn.fnamemodify(path, ":~"))
		vim.ui.open(path)
	end)
end

-- ============================================================================
-- Main file
-- ============================================================================

-- A document split across files compiles from its root, not from the chapter
-- being edited. Pinning tells tinymist which file that is, so diagnostics and
-- preview keep describing the whole document while you work inside a part of it.
function M.pin()
	local path = current_path()
	exec("tinymist.pinMain", { path }, function()
		notify("compiling from " .. vim.fn.fnamemodify(path, ":t"))
	end)
end

-- Passing null hands the choice back to the server, which returns to treating
-- whichever file is focused as the root.
function M.unpin()
	exec("tinymist.pinMain", { vim.NIL }, function()
		notify("unpinned — compiling from the focused file")
	end)
end

-- ============================================================================
-- Commands and keymaps
-- ============================================================================

local command = vim.api.nvim_create_user_command
command("TypstPreview", M.preview, { desc = "live preview this document in a browser" })
command("TypstPreviewStop", M.stop_preview, { desc = "stop the typst preview server" })
command("TypstPdf", M.pdf, { desc = "export this document to PDF and open it" })
command("TypstPin", M.pin, { desc = "compile the project from this file" })
command("TypstUnpin", M.unpin, { desc = "compile from whichever file is focused" })

-- Buffer-local: none of these mean anything outside a .typ file, and a global
-- <leader>t would stall on the timeout everywhere else.
vim.api.nvim_create_autocmd("FileType", {
	pattern = "typst",
	callback = function(args)
		local map = function(lhs, rhs, desc)
			vim.keymap.set("n", lhs, rhs, { buffer = args.buf, desc = desc })
		end

		map("<leader>tp", M.toggle_preview, "toggle preview")
		map("<leader>te", M.pdf, "export PDF")
		map("<leader>tm", M.pin, "pin as main file")
		map("<leader>tM", M.unpin, "unpin main file")

		local ok, wk = pcall(require, "which-key")
		if ok then
			wk.add({ { "<leader>t", group = "typst", buffer = args.buf } })
		end
	end,
})

-- Leaving nvim with a preview still up would orphan the server and hold its
-- port; the same reasoning as the notes-site server.
vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		if state.addr then
			M.stop_preview()
		end
	end,
})

return M
