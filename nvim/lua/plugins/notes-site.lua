-- Drive the notes-site preview server without leaving nvim.
--
-- notes-site (~/repos/notes-site) regenerates a Hugo site from the zk notebook
-- and reloads the browser as notes are saved. This starts and stops the server
-- and points a browser at the right page.
--
-- It also drives the drawing editor the server can host, which is the one part
-- of this that puts a file in the notebook: a new .excalidraw scene, created
-- empty here and then written by the editor in the browser as you draw.

local config = {
	site = vim.env.NOTES_SITE_DIR or vim.fn.expand("~/repos/notes-site"),
	notebook = vim.env.ZK_NOTEBOOK_DIR or vim.fn.expand("~/notes"),
	port = tonumber(vim.env.NOTES_SITE_PORT) or 1313,
	draw_port = tonumber(vim.env.NOTES_SITE_DRAW_PORT) or 1314,
	-- Where a new drawing is filed, relative to the notebook root.
	drawings = "diagrams",
}

local M = {}

local state = {
	job = nil,
	log = {},
}

local function url(path)
	return ("http://localhost:%d%s"):format(config.port, path or "/")
end

-- The editor listens on its own port; Hugo owns the other one outright.
local function draw_url(rel)
	return ("http://localhost:%d/draw/?file=%s"):format(config.draw_port, vim.uri_encode(rel))
end

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = "notes-site" })
end

local function record(line)
	if line == "" then
		return
	end
	table.insert(state.log, line)
	-- Keep the log bounded; a long session would otherwise grow without limit.
	if #state.log > 500 then
		table.remove(state.log, 1)
	end
	-- Surface only what needs acting on. Sync summaries go to the log.
	if line:match("failed") or line:match("[Ee]rror") then
		notify(line, vim.log.levels.WARN)
	end
end

local function collect(err, data)
	if err or not data then
		return
	end
	for line in data:gmatch("[^\r\n]+") do
		vim.schedule(function()
			record(line)
		end)
	end
end

function M.running()
	return state.job ~= nil
end

-- start builds the binary first, so an edit to the Go side takes effect without
-- having to remember to rebuild.
function M.start()
	if M.running() then
		notify("already running at " .. url())
		return
	end
	if vim.fn.isdirectory(config.site) == 0 then
		notify("no site at " .. config.site .. " (set $NOTES_SITE_DIR)", vim.log.levels.ERROR)
		return
	end

	local build = vim.system({ "make", "bin/serve" }, { cwd = config.site, text = true }):wait()
	if build.code ~= 0 then
		notify("build failed:\n" .. (build.stderr or ""), vim.log.levels.ERROR)
		return
	end

	state.log = {}
	-- serve is spawned directly rather than through `make`, so that stopping it
	-- signals the process that owns hugo instead of an intermediate shell.
	state.job = vim.system({
		config.site .. "/bin/serve",
		"--notebook",
		config.notebook,
		-- Opt in to the drawing editor. Without this the server only ever reads
		-- the notebook, which is its default and the safer one.
		"--edit-drawings",
		"--draw-port",
		tostring(config.draw_port),
		"--",
		"--port",
		tostring(config.port),
	}, {
		cwd = config.site,
		text = true,
		stdout = collect,
		stderr = collect,
	}, function(out)
		vim.schedule(function()
			state.job = nil
			if out.code ~= 0 and out.signal == 0 then
				notify("server exited (" .. out.code .. ") — :NotesSiteLog", vim.log.levels.ERROR)
			end
		end)
	end)

	notify("serving " .. config.notebook .. " at " .. url())
end

function M.stop()
	if not M.running() then
		notify("not running")
		return
	end
	-- serve handles SIGTERM by shutting hugo down too.
	state.job:kill("sigterm")
	state.job = nil
	notify("stopped")
end

function M.toggle()
	if M.running() then
		M.stop()
	else
		M.start()
	end
end

-- wait_ready polls the port rather than guessing at a delay, so the browser is
-- only opened once there is something to show.
local function wait_ready(port, attempts, callback)
	local sock = vim.uv.new_tcp()
	sock:connect("127.0.0.1", port, function(err)
		sock:close()
		if not err then
			vim.schedule(callback)
		elseif attempts > 0 then
			vim.defer_fn(function()
				wait_ready(port, attempts - 1, callback)
			end, 250)
		else
			vim.schedule(function()
				notify("port " .. port .. " did not come up — :NotesSiteLog", vim.log.levels.ERROR)
			end)
		end
	end)
end

-- open_url starts the server if it is not up, then waits for the port it needs
-- before handing the address to the browser.
local function open_url(target, port)
	if not M.running() then
		M.start()
		if not M.running() then
			return
		end
	end
	wait_ready(port, 40, function()
		vim.ui.open(target)
	end)
end

local function open(path)
	open_url(url(path), config.port)
end

function M.open()
	open("/")
end

-- The zk id of the note in the current buffer: its front matter `id`, falling
-- back to the filename, which is what the notebook's template names files by.
local function note_id(buf)
	for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, 20, false)) do
		local id = line:match("^id:%s*(%S+)")
		if id then
			return id
		end
		if i > 1 and line:match("^%-%-%-%s*$") then
			break -- end of the front matter block
		end
	end
	return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
end

-- The site's URL for a note is read out of the page notes-site generated for
-- it, rather than derived here. Slugs come from titles via rules that include
-- transliteration, and there is no reason to have a second implementation of
-- them that can drift.
function M.note_path(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local id = note_id(buf)
	if id == "" then
		return nil, "buffer is not a file"
	end

	local generated = ("%s/content/notes/%s.md"):format(config.site, id)
	local file = io.open(generated, "r")
	if not file then
		return nil, ("no page for %s yet — is it published, and has the site synced?"):format(id)
	end

	local i = 0
	for line in file:lines() do
		i = i + 1
		local slug = line:match('^slug:%s*"(.-)"')
		if slug then
			file:close()
			return "/notes/" .. slug .. "/"
		end
		if i > 1 and line:match("^%-%-%-%s*$") then
			break -- end of the front matter block
		end
	end
	file:close()
	return nil, ("could not read a slug for %s"):format(id)
end

function M.preview()
	local path, err = M.note_path()
	if not path then
		notify(err, vim.log.levels.WARN)
		return
	end
	open(path)
end

-- ============================================================================
-- Drawings
-- ============================================================================

-- slugify turns what was typed into something safe to use as a filename.
local function slugify(s)
	s = s:lower():gsub("[^%w%s-]", ""):gsub("%s+", "-"):gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
	return s
end

-- segments splits a normalised path into its non-empty parts.
local function segments(p)
	local out = {}
	for s in vim.fs.normalize(p):gmatch("[^/]+") do
		out[#out + 1] = s
	end
	return out
end

-- relative_href is the path from one directory to one file, walking up with
-- ".." where it has to.
--
-- vim.fs.relpath is not enough here: it returns nil rather than a "../" path
-- whenever the target is not underneath the base, which is exactly the case a
-- note in a subdirectory hits.
local function relative_href(from_dir, to_file)
	local from, to = segments(from_dir), segments(to_file)

	local same = 0
	while same < #from and same < #to and from[same + 1] == to[same + 1] do
		same = same + 1
	end

	local parts = {}
	for _ = same + 1, #from do
		parts[#parts + 1] = ".."
	end
	for i = same + 1, #to do
		parts[#parts + 1] = to[i]
	end
	return table.concat(parts, "/")
end

-- reference_to builds the href a note should use for a drawing.
--
-- notes-site resolves a drawing reference relative to the note that makes it,
-- so a note in a subdirectory needs a path back out to the drawings directory.
local function reference_to(note_path, drawing_rel)
	local note_dir = vim.fn.fnamemodify(note_path, ":h")
	return relative_href(note_dir, config.notebook .. "/" .. drawing_rel)
end

local empty_scene =
	'{\n  "type": "excalidraw",\n  "version": 2,\n  "source": "notes-site",\n  "elements": [],\n  "appState": {},\n  "files": {}\n}\n'

-- new_drawing files an empty scene in the notebook, references it from the
-- note being edited, and opens it in the browser to draw.
function M.new_drawing()
	local buf = vim.api.nvim_get_current_buf()
	local note = vim.api.nvim_buf_get_name(buf)

	vim.ui.input({ prompt = "Drawing name: " }, function(input)
		if not input or input == "" then
			return
		end
		local name = slugify(input)
		if name == "" then
			notify("that name leaves nothing usable as a filename", vim.log.levels.WARN)
			return
		end

		local rel = ("%s/%s.excalidraw"):format(config.drawings, name)
		local full = ("%s/%s"):format(config.notebook, rel)

		if vim.fn.filereadable(full) == 1 then
			notify(rel .. " already exists — opening it", vim.log.levels.WARN)
		else
			vim.fn.mkdir(vim.fn.fnamemodify(full, ":h"), "p")
			local file, err = io.open(full, "w")
			if not file then
				notify("could not create " .. rel .. ": " .. tostring(err), vim.log.levels.ERROR)
				return
			end
			file:write(empty_scene)
			file:close()
		end

		-- Only touch the buffer when it is a note; the drawing is still usable
		-- from anywhere else, it just has nowhere to be referenced from.
		if note ~= "" and vim.bo[buf].filetype == "markdown" then
			local href = reference_to(note, rel)
			local line = ("![%s](%s)"):format(input, href)
			local row = vim.api.nvim_win_get_cursor(0)[1]
			vim.api.nvim_buf_set_lines(buf, row, row, false, { "", line })
			vim.api.nvim_win_set_cursor(0, { row + 2, 0 })
		end

		open_url(draw_url(rel), config.draw_port)
	end)
end

-- drawing_under_cursor reads a drawing reference off the current line and
-- resolves it the way notes-site would: relative to the note.
local function drawing_under_cursor()
	local line = vim.api.nvim_get_current_line()
	local href = line:match("%]%(([^)]-%.excalidraw)%)") or line:match("([%w%-_/%.]+%.excalidraw)")
	if not href then
		return nil
	end

	local note_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h")
	local full = vim.fs.normalize(note_dir .. "/" .. href)
	local rel = vim.fs.relpath(vim.fs.normalize(config.notebook), full)
	return rel or href
end

-- edit_drawing opens the drawing referenced on the current line.
function M.edit_drawing()
	local rel = drawing_under_cursor()
	if not rel then
		notify("no .excalidraw reference on this line", vim.log.levels.WARN)
		return
	end
	open_url(draw_url(rel), config.draw_port)
end

function M.show_log()
	if #state.log == 0 then
		notify("nothing logged yet")
		return
	end
	vim.cmd("botright new")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, state.log)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_set_name(buf, "notes-site log")
end

local command = vim.api.nvim_create_user_command
command("NotesSiteStart", M.start, { desc = "start the notes-site preview server" })
command("NotesSiteStop", M.stop, { desc = "stop the notes-site preview server" })
command("NotesSiteToggle", M.toggle, { desc = "toggle the notes-site preview server" })
command("NotesSiteOpen", M.open, { desc = "open the site in a browser" })
command("NotesSitePreview", M.preview, { desc = "open this note's page in a browser" })
command("NotesSiteLog", M.show_log, { desc = "show the preview server's output" })
command("DrawNew", M.new_drawing, { desc = "new excalidraw drawing, referenced from this note" })
command("DrawEdit", M.edit_drawing, { desc = "edit the drawing referenced on this line" })

vim.keymap.set("n", "<leader>zs", M.toggle, { desc = "toggle preview server" })
vim.keymap.set("n", "<leader>zp", M.preview, { desc = "preview note in browser" })
vim.keymap.set("n", "<leader>zP", M.open, { desc = "open site in browser" })

vim.keymap.set("n", "<leader>dn", M.new_drawing, { desc = "new drawing" })
vim.keymap.set("n", "<leader>de", M.edit_drawing, { desc = "edit drawing on this line" })

-- Leaving nvim with a server still running would orphan it and hold the port.
vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		if M.running() then
			state.job:kill("sigterm")
		end
	end,
})

return M
