-- Notebook location, so :Zk* commands work from any buffer, not just inside it.
vim.env.ZK_NOTEBOOK_DIR = vim.env.ZK_NOTEBOOK_DIR or vim.fn.expand("~/notes")

require("zk").setup({
	picker = "telescope",

	lsp = {
		config = {
			name = "zk",
			cmd = { "zk", "lsp" },
			filetypes = { "markdown" },
		},
		-- Attaches only for markdown files that live inside a notebook.
		auto_attach = {
			enabled = true,
		},
	},

	tags = {
		multi_select_strategy = "AND",
	},
})

local zk = require("zk")
local commands = require("zk.commands")

local M = {}

local map = function(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { desc = desc })
end

map("n", "<leader>zn", function()
	zk.new({ title = vim.fn.input("Title: ") })
end, "new note")

map("n", "<leader>zo", function()
	zk.edit({ sort = { "modified" } }, { title = "zk: notes" })
end, "open note")

map("n", "<leader>zf", function()
	zk.edit({ sort = { "modified" }, match = { vim.fn.input("Search: ") } }, { title = "zk: search" })
end, "search notes")

map("n", "<leader>zt", "<Cmd>ZkTags<CR>", "tags")
-- zb and zl go through the wrappers at the bottom of this file rather than
-- :ZkBacklinks and :ZkLinks, which cannot see embedded notes.
map("n", "<leader>zb", function()
	M.backlinks()
end, "backlinks")
map("n", "<leader>zl", function()
	M.links()
end, "outgoing links")

-- Visual mode: turn a selection into a new note, or search for it.
map("v", "<leader>zn", ":'<,'>ZkNewFromTitleSelection<CR>", "new note from selection (title)")
map("v", "<leader>zN", ":'<,'>ZkNewFromContentSelection<CR>", "new note from selection (content)")
map("v", "<leader>zf", ":'<,'>ZkMatch<CR>", "search for selection")
map("v", "<leader>zi", ":'<,'>ZkInsertLinkAtSelection<CR>", "link selection to a note")

-- Markdown-only mappings, active in notebook buffers.
vim.api.nvim_create_autocmd("FileType", {
	pattern = "markdown",
	callback = function(args)
		vim.keymap.set("n", "<leader>zi", "<Cmd>ZkInsertLink<CR>", {
			buffer = args.buf,
			desc = "insert link to a note",
		})
	end,
})

-- `zk list` supports arbitrary filters; this one is handy enough to keep around.
commands.add("ZkOrphans", function(options)
	options = vim.tbl_extend("force", { orphan = true }, options or {})
	zk.edit(options, { title = "zk: orphans" })
end)

-- ============================================================================
-- Embedded notes
-- ============================================================================
--
-- zk does not index `![[note]]`. Its markdown parser reads the `!` form as an
-- image, so an embedded note never reaches the link database: `zk list
-- --linked-by` and `--link-to` both come back empty for one, and the language
-- server answers no definition on it. `[[note]]` is indexed normally — the
-- exclamation mark is the whole of the difference.
--
-- For a notebook built out of transclusions that is most of the links. r2vn
-- embeds four notes and links to none, so :ZkLinks there had nothing to show,
-- and the four notes it embeds each reported no backlinks.
--
-- There is no setting for it: [format.markdown] takes link-format,
-- link-encode-path, link-drop-extension and the tag options, and nothing else.
-- So embeds are collected here and merged into zk's answer rather than
-- replacing it — zk still resolves ordinary links, links written in markdown
-- format, and links that name a note by title, none of which a scan for
-- `[[...]]` would find.

local api = require("zk.api")
local ui = require("zk.ui")

local function notebook()
	return vim.env.ZK_NOTEBOOK_DIR
end

-- Every wiki target on a line: [[id]], ![[id]], [[id|alias]], [[id#heading]].
-- The leading '!' sits outside the pattern deliberately — that is what lets one
-- pattern find embeds and plain links alike.
local WIKI = "%[%[([^%[%]|#]+)"

-- The file a link names. Notes are named by id (filename = "{{id}}" in
-- .zk/config.toml), so this is usually a direct hit; the search is for notes
-- filed in a subdirectory. Returns nil for a link that names a note by title,
-- which is zk's business to resolve, not ours.
local function note_file(id)
	local direct = notebook() .. "/" .. id .. ".md"
	if vim.fn.filereadable(direct) == 1 then
		return direct
	end
	return vim.fs.find(id .. ".md", { path = notebook(), type = "file", limit = 1 })[1]
end

-- ============================================================================
-- Following a link
-- ============================================================================

-- The id of the wiki link under the cursor, if it is on one.
local function link_under_cursor()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	local from = 1

	while true do
		local open, stop, id = line:find(WIKI, from)
		if not open then
			return nil
		end
		-- The capture stops at the first ] | or #, so the link runs to its
		-- closing brackets, not to the end of the id.
		local close = line:find("%]%]", stop)
		if col >= open and col <= (close and close + 1 or stop) then
			return vim.trim(id)
		end
		from = stop + 1
	end
end

---Follow the wiki link under the cursor. Returns true when it handled the jump,
---false to leave the keypress to whoever asked.
function M.follow_wiki_link()
	local id = link_under_cursor()
	if not id then
		return false
	end
	local file = note_file(id)
	if not file then
		-- Not a filename. It may still be a title the server can resolve, so
		-- this is not the place to report a broken link.
		return false
	end
	vim.cmd("edit " .. vim.fn.fnameescape(file))
	return true
end

-- ============================================================================
-- Links and backlinks
-- ============================================================================

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "zk" })
end

-- zk's own answer, with the fields the configured picker needs.
local function list(options, cb)
	api.list(
		notebook(),
		vim.tbl_extend("force", { select = ui.get_pick_notes_list_api_selection({}) }, options),
		function(err, notes)
			cb((not err and notes) or {})
		end
	)
end

-- Merge zk's notes with the ones only the embed scan found, and pick from the
-- result. The extra paths go back through `zk list` so their titles come from
-- the same place as everything else in the list.
local function pick(title, filter, extra)
	list(filter, function(from_zk)
		local function show(from_embeds)
			local seen, merged = {}, {}
			for _, notes in ipairs({ from_zk, from_embeds }) do
				for _, note in ipairs(notes) do
					if note.absPath and not seen[note.absPath] then
						seen[note.absPath] = true
						merged[#merged + 1] = note
					end
				end
			end

			if #merged == 0 then
				notify(title:lower() .. ": none")
				return
			end

			ui.pick_notes(merged, { title = title }, function(selected)
				for _, note in ipairs(selected) do
					vim.cmd("edit " .. vim.fn.fnameescape(note.absPath))
				end
			end)
		end

		if #extra == 0 then
			show({})
		else
			list({ hrefs = extra }, show)
		end
	end)
end

---Notes this one links to, embeds included.
function M.links()
	local extra = {}
	local seen = {}
	for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
		for id in line:gmatch(WIKI) do
			local file = note_file(vim.trim(id))
			if file and not seen[file] then
				seen[file] = true
				extra[#extra + 1] = file
			end
		end
	end
	pick("Zk Links", { linkedBy = { vim.api.nvim_buf_get_name(0) } }, extra)
end

-- Regex metacharacters, escaped for the search tool. Note ids are alphanumeric,
-- but a note filed under a hand-written name need not be.
local function escape(s)
	return (s:gsub("[%^%$%.%[%]%*%+%-%?%(%)%{%}|\\/]", "\\%0"))
end

---Notes linking to this one, embeds included.
--
-- zk cannot answer the embed half, and there is nothing in its index to ask, so
-- this is a search across the notebook. `[[id` matches the embedded form too,
-- the '!' being the only thing in front of it.
function M.backlinks()
	local path = vim.api.nvim_buf_get_name(0)
	local id = vim.fn.fnamemodify(path, ":t:r")
	local pattern = ("\\[\\[%s(\\]|\\||#)"):format(escape(id))

	local cmd
	if vim.fn.executable("rg") == 1 then
		cmd = { "rg", "--files-with-matches", "--no-messages", "--glob", "*.md", "-e", pattern, notebook() }
	else
		cmd = { "grep", "-rlE", "--include=*.md", pattern, notebook() }
	end

	vim.system(cmd, { text = true }, function(out)
		local extra = {}
		for file in (out.stdout or ""):gmatch("[^\n]+") do
			-- A note that embeds itself is not a backlink.
			if vim.fs.normalize(file) ~= vim.fs.normalize(path) then
				extra[#extra + 1] = file
			end
		end
		vim.schedule(function()
			pick("Zk Backlinks", { linkTo = { path } }, extra)
		end)
	end)
end

return M
