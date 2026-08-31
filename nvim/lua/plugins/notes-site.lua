-- Drive the notes-site preview server without leaving nvim.
--
-- notes-site (~/repos/notes-site) regenerates a Hugo site from the zk notebook
-- and reloads the browser as notes are saved. This starts and stops the server
-- and points a browser at the right page.
--
-- Two parts of it put a file *in* the notebook rather than reading one. The
-- drawing editor the server can host writes a new .excalidraw scene, created
-- empty here and filled in by the editor in the browser as you draw. And filing
-- an exercise runs notes-site's own `newexercise`, which writes one .typ under
-- the notebook's exercises tree and opens it here to write in.

local config = {
	site = vim.env.NOTES_SITE_DIR or vim.fn.expand("~/repos/notes-site"),
	notebook = vim.env.ZK_NOTEBOOK_DIR or vim.fn.expand("~/notes"),
	port = tonumber(vim.env.NOTES_SITE_PORT) or 1313,
	draw_port = tonumber(vim.env.NOTES_SITE_DRAW_PORT) or 1314,
	-- Where a new drawing is filed, relative to the notebook root.
	drawings = "diagrams",
	-- The tree whose .typ files publish themselves, relative to the notebook
	-- root. Matches notes-site's own -exercises-dir, and names the site section
	-- they are published into, which notes-site keeps the same.
	exercises = "exercises",
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

-- ensure_binary builds one of notes-site's commands, so that an edit to the Go
-- side takes effect without having to remember to rebuild. Reports what went
-- wrong and returns false rather than leaving the caller to.
local function ensure_binary(name)
	if vim.fn.isdirectory(config.site) == 0 then
		notify("no site at " .. config.site .. " (set $NOTES_SITE_DIR)", vim.log.levels.ERROR)
		return false
	end
	local build = vim.system({ "make", "bin/" .. name }, { cwd = config.site, text = true }):wait()
	if build.code ~= 0 then
		notify("build failed:\n" .. (build.stderr or ""), vim.log.levels.ERROR)
		return false
	end
	return true
end

function M.start()
	if M.running() then
		notify("already running at " .. url())
		return
	end
	if not ensure_binary("serve") then
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

-- front_matter reads the scalar fields out of a page notes-site generated.
-- Every one of them is written quoted, which is what makes this enough.
local function front_matter(path)
	local out = {}
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local i = 0
	for line in file:lines() do
		i = i + 1
		local key, value = line:match('^(%w+):%s*"(.-)"%s*$')
		if key then
			out[key] = value
		end
		if i > 1 and line:match("^%-%-%-%s*$") then
			break -- end of the front matter block
		end
	end
	file:close()
	return out
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

	local front = front_matter(("%s/content/notes/%s.md"):format(config.site, id))
	if not front then
		return nil, ("no page for %s yet — is it published, and has the site synced?"):format(id)
	end
	if not front.slug then
		return nil, ("could not read a slug for %s"):format(id)
	end
	return "/notes/" .. front.slug .. "/"
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

-- ============================================================================
-- Exercises
-- ============================================================================
--
-- An exercise is a .typ file under `exercises/` in the notebook. It publishes
-- itself — notes-site walks that tree rather than waiting for a note to cite
-- one — so nothing here is about making an exercise appear. What is here is
-- about writing them: filing a new one, finding one again, and moving between
-- an exercise and the note it was set from.
--
-- The file itself is created by notes-site's own `newexercise` rather than
-- written here. That command owns the template, the naming, and the refusal to
-- overwrite anything, and a second implementation of those in Lua would only be
-- a second thing to keep in step.

-- The statuses the site gives a colour to. It takes any word at all and labels
-- an unknown one with itself, so this is a list of the usual ones rather than a
-- vocabulary — to use another, edit the line.
local statuses = { "draft", "wip", "stuck", "done", "handed-in", "graded" }

-- Remembered across one session, so that filing a run of exercises for a course
-- does not mean typing its name every time.
local last_course = nil

-- notebook_rel is where a file sits inside the notebook, or nil for one that is
-- somewhere else entirely.
local function notebook_rel(path)
	if path == nil or path == "" then
		return nil
	end
	return vim.fs.relpath(vim.fs.normalize(config.notebook), vim.fs.normalize(path))
end

-- current_note_id is the zk id of this buffer, but only when it really is a
-- note in the notebook. note_id falls back to a filename, which on its own
-- would make every markdown file anywhere look like one.
local function current_note_id(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if vim.bo[buf].filetype ~= "markdown" then
		return nil
	end
	if not notebook_rel(vim.api.nvim_buf_get_name(buf)) then
		return nil
	end
	local id = note_id(buf)
	return id ~= "" and id or nil
end

-- describe reads what an exercise declares about itself, out of the
-- `#show: exercise.with(...)` call at the top of the file.
--
-- This is the same metadata notes-site reads back with `typst eval`, read here
-- the cheap way. It labels a picker; it does not generate a page, and running
-- Typst once per file to fill in a list would cost seconds to save nothing.
local function describe(path)
	local head = {}
	local file = io.open(path, "r")
	if not file then
		return {}
	end
	for _ = 1, 20 do
		local line = file:read("l")
		if not line then
			break
		end
		head[#head + 1] = line
	end
	file:close()

	local blob = table.concat(head, "\n")
	local function field(name)
		return blob:match(name .. ':%s*"([^"]*)"')
	end
	-- The kind is the one thing not written in the file: it lives inside the
	-- template, which is where notes-site reads it from with `typst eval`.
	-- Here the show rule names the template it came from — `assignment.with(`
	-- or `exercise.with(` — which is the same answer for the cost of a match.
	-- An explicit field still wins, for a file that declares one itself.
	return {
		kind = field("kind") or blob:match("#show:%s*(%w+)%.with%("),
		course = field("course"),
		number = field("number"),
		title = field("title"),
		status = field("status"),
		due = field("due"),
		source = field("source"),
	}
end

-- label names an exercise in a list the way the site does: by its course and
-- number, which is how one is referred to, with the title after.
--
-- An exercise that never got a title is left as its course and number alone.
-- The filename is only worth falling back to when there is nothing else, since
-- notes-site names the file from the number — "LinAlg 2.10 — 2-10" is the same
-- thing said twice.
local function label(meta, rel)
	-- "IPSRP Assignment 3" where it is a hand-in, "IPSRP 1.1" where it is not:
	-- a course is mostly exercises, and saying so on every one of them would
	-- bury the two that are not.
	local noun = nil
	if meta.kind and meta.kind ~= "" and meta.kind ~= "exercise" then
		noun = meta.kind:sub(1, 1):upper() .. meta.kind:sub(2)
	end

	local head = table.concat(vim.tbl_filter(function(s)
		return s ~= nil and s ~= ""
	end, { meta.course, noun, meta.number }), " ")

	local title = meta.title
	if title == "" then
		title = nil
	end

	if title and head ~= "" then
		return head .. " — " .. title
	end
	return title or (head ~= "" and head) or vim.fn.fnamemodify(rel, ":t:r")
end

-- all_exercises finds every exercise in the notebook, most recently worked on
-- first — the same order `zk edit` lists notes in, and for the same reason.
--
-- The notebook is walked rather than the generated content read, unlike
-- note_path above: this list is for opening a file to write in, so it has to
-- answer for an exercise filed a moment ago, before any sync has run.
local function all_exercises()
	local root = vim.fs.normalize(config.notebook .. "/" .. config.exercises)

	local found = vim.fs.find(function(name, dir)
		if not name:match("%.typ$") or name:match("^[._]") then
			return false
		end
		-- notes-site skips a directory beginning with "." or "_", so a file
		-- inside one is not an exercise however it is named.
		for segment in vim.fs.normalize(dir):sub(#root + 1):gmatch("[^/]+") do
			if segment:match("^[._]") then
				return false
			end
		end
		return true
	end, { path = root, type = "file", limit = math.huge })

	local out = {}
	for _, path in ipairs(found) do
		local stat = vim.uv.fs_stat(path)
		local rel = notebook_rel(path) or path
		local meta = describe(path)
		out[#out + 1] = {
			path = path,
			rel = rel,
			meta = meta,
			label = label(meta, rel),
			mtime = stat and stat.mtime.sec or 0,
		}
	end

	table.sort(out, function(a, b)
		if a.mtime ~= b.mtime then
			return a.mtime > b.mtime
		end
		return a.rel < b.rel
	end)
	return out
end

-- choose puts a list of exercises in front of you, with the status and due date
-- alongside, since between two exercises those are usually what tells them
-- apart when the numbers do not.
local function choose(prompt, list, callback)
	if #list == 0 then
		notify("no exercises in " .. config.exercises .. "/ yet")
		return
	end
	vim.ui.select(list, {
		prompt = prompt,
		format_item = function(item)
			local marks = {}
			if item.meta.status and item.meta.status ~= "" then
				marks[#marks + 1] = item.meta.status
			end
			if item.meta.due and item.meta.due ~= "" then
				marks[#marks + 1] = "due " .. item.meta.due
			end
			if #marks == 0 then
				return item.label
			end
			return ("%s  (%s)"):format(item.label, table.concat(marks, ", "))
		end,
	}, function(chosen)
		if chosen then
			callback(chosen)
		end
	end)
end

-- open_exercise edits the file and leaves the cursor where the writing starts,
-- which is inside the statement block the template files empty.
local function open_exercise(path)
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if line:match("#statement%[") then
			local row = math.min(i + 1, vim.api.nvim_buf_line_count(buf))
			local text = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
			vim.api.nvim_win_set_cursor(0, { row, #text })
			return
		end
	end
end

-- parse_spec reads "IPSRP 1.1 De Morgan for n sets @2026-09-08" into its parts.
--
-- One prompt rather than four, because filing an exercise happens constantly
-- while working through a problem set, and four sequential inputs for what is
-- one thought is three too many. The course is the first word; the next is the
-- number when it begins with a digit; a word starting with "@" is the due date
-- wherever it appears; the rest is the title.
local function parse_spec(spec)
	local words, due = {}, nil
	for word in spec:gmatch("%S+") do
		local date = word:match("^@(.+)$")
		if date then
			due = date
		else
			words[#words + 1] = word
		end
	end

	local course = table.remove(words, 1)
	local number
	if words[1] and words[1]:match("^%d") then
		number = table.remove(words, 1)
	end
	return course, number, table.concat(words, " "), due
end

-- new_exercise files one in the notebook and opens it.
--
-- Filed from a note, it is told which note that was. That is the whole of the
-- link between the two: the exercise names its source, and the site reads it
-- from there to give the note its "Exercises" section. Nothing is written into
-- the note itself — see insert_reference for the case where the exercise
-- belongs in the middle of a sentence rather than merely beside it.
function M.new_exercise(kind)
	kind = kind or "exercise"
	local note = current_note_id()

	vim.ui.input({
		prompt = ("%s (course number title): "):format(kind:sub(1, 1):upper() .. kind:sub(2)),
		default = last_course and (last_course .. " ") or "",
	}, function(input)
		if not input or vim.trim(input) == "" then
			return
		end

		local course, number, title, due = parse_spec(input)
		if not course then
			return
		end
		if not number and title == "" then
			notify("give it a course and a number, e.g. IPSRP 1.1", vim.log.levels.WARN)
			return
		end
		last_course = course

		if not ensure_binary("newexercise") then
			return
		end

		local args = {
			config.site .. "/bin/newexercise",
			"--notebook",
			config.notebook,
			"--dir",
			config.exercises,
			"--kind",
			kind,
			"--course",
			course,
			-- Prints where the file went and opens nothing: the editor to open
			-- it in is this one, already running.
			"--print-path",
		}
		local function flag(name, value)
			if value and value ~= "" then
				vim.list_extend(args, { name, value })
			end
		end
		flag("--number", number)
		flag("--title", title)
		flag("--due", due)
		flag("--note", note)

		local out = vim.system(args, { text = true }):wait()
		if out.code ~= 0 then
			notify(vim.trim(out.stderr or "newexercise failed"), vim.log.levels.ERROR)
			return
		end

		local path = vim.trim(out.stdout or "")
		if path == "" then
			notify("newexercise reported no path", vim.log.levels.ERROR)
			return
		end

		vim.schedule(function()
			open_exercise(path)
			if note then
				notify(("%s — set from %s"):format(notebook_rel(path) or path, note))
			else
				notify(notebook_rel(path) or path)
			end
		end)
	end)
end

-- new_assignment is the same act with the other template: several numbered
-- problems, a cover naming who is handing it in, and a PDF that is the point
-- rather than a convenience.
function M.new_assignment()
	M.new_exercise("assignment")
end

-- find opens any exercise in the notebook.
function M.find()
	choose("Exercise:", all_exercises(), function(chosen)
		open_exercise(chosen.path)
	end)
end

-- note_exercises opens one of the exercises set from the note being edited,
-- which is the other end of an exercise's own source.
function M.note_exercises()
	local id = current_note_id()
	if not id then
		notify("not a note in " .. config.notebook, vim.log.levels.WARN)
		return
	end

	local matching = vim.tbl_filter(function(e)
		return e.meta.source == id
	end, all_exercises())

	if #matching == 0 then
		notify("nothing set from " .. id .. " yet")
		return
	end
	choose("Exercises from " .. id .. ":", matching, function(chosen)
		open_exercise(chosen.path)
	end)
end

-- exercise_under_cursor reads a .typ reference off the current line and
-- resolves it the way notes-site would: relative to the note making it.
local function exercise_under_cursor()
	local line = vim.api.nvim_get_current_line()
	local href = line:match("%]%(([^)]-%.typ)%)") or line:match("([%w%-_/%.]+%.typ)")
	if not href then
		return nil
	end
	local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h")
	return vim.fs.normalize(dir .. "/" .. href)
end

-- edit_exercise opens the exercise referenced on the current line.
function M.edit_exercise()
	local path = exercise_under_cursor()
	if not path then
		notify("no .typ reference on this line", vim.log.levels.WARN)
		return
	end
	if vim.fn.filereadable(path) == 0 then
		notify("no file at " .. (notebook_rel(path) or path), vim.log.levels.WARN)
		return
	end
	open_exercise(path)
end

-- set_status rewrites how far along the exercise being edited is.
function M.set_status()
	local buf = vim.api.nvim_get_current_buf()
	local rel = notebook_rel(vim.api.nvim_buf_get_name(buf))
	if not rel or not rel:match("^" .. vim.pesc(config.exercises) .. "/") then
		notify("not an exercise under " .. config.exercises .. "/", vim.log.levels.WARN)
		return
	end

	vim.ui.select(statuses, { prompt = "Status:" }, function(choice)
		if not choice then
			return
		end
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

		for i, line in ipairs(lines) do
			if line:match('status:%s*"[^"]*"') then
				local updated = line:gsub('(status:%s*")[^"]*"', "%1" .. choice .. '"', 1)
				vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { updated })
				notify("status: " .. choice)
				return
			end
		end

		-- No status declared yet. It goes into the call that ought to carry it,
		-- but only where that call is written a field to a line: adding one to
		-- `exercise.with(course: "X")` would need the line rewritten rather
		-- than added to, and guessing at that is how a file gets broken.
		for i, line in ipairs(lines) do
			if line:match("#show:%s*exercise%.with%(%s*$") then
				vim.api.nvim_buf_set_lines(buf, i, i, false, { ('  status: "%s",'):format(choice) })
				notify("status: " .. choice)
				return
			end
		end
		notify("no status: line to change — add one to the exercise.with call", vim.log.levels.WARN)
	end)
end

-- The site's URL for an exercise, read out of the page notes-site generated for
-- it. As with note_path, the slug is not rebuilt here: it comes from the course
-- and number through rules that include transliteration, and a second
-- implementation of those would drift from the first.
function M.exercise_path(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local rel = notebook_rel(vim.api.nvim_buf_get_name(buf))
	if not rel then
		return nil, "not a file in " .. config.notebook
	end

	local dir = ("%s/content/%s"):format(config.site, config.exercises)
	for name, kind in vim.fs.dir(dir) do
		if kind == "file" and name:match("%.md$") and name ~= "_index.md" then
			local front = front_matter(dir .. "/" .. name)
			if front.source == rel and front.slug then
				return ("/%s/%s/"):format(config.exercises, front.slug)
			end
		end
	end
	return nil, ("no page for %s yet — has the site synced?"):format(rel)
end

-- preview_exercise opens this exercise's page on the site, which is the one
-- that shows it as a reader sees it: its own typography, its status, and the
-- notes around it. tinymist's own preview (<leader>tp) shows the document
-- alone, which is the other thing you want and a different one.
function M.preview_exercise()
	local path, err = M.exercise_path()
	if not path then
		notify(err, vim.log.levels.WARN)
		return
	end
	open(path)
end

-- open_exercises opens the catalogue, grouped by course.
function M.open_exercises()
	open("/" .. config.exercises .. "/")
end

-- insert_reference writes a reference to an exercise into the note being
-- edited, and is deliberately not what filing one does. An exercise reaches the
-- site on its own and already names the note it was set from, so the ordinary
-- link between the two needs nothing in the prose. This is for the other case:
-- when the exercise is part of what the note is saying and belongs in the
-- middle of a sentence.
function M.insert_reference()
	local buf = vim.api.nvim_get_current_buf()
	local note = vim.api.nvim_buf_get_name(buf)
	if vim.bo[buf].filetype ~= "markdown" or note == "" then
		notify("not a note", vim.log.levels.WARN)
		return
	end

	choose("Reference which exercise?", all_exercises(), function(chosen)
		local href = relative_href(vim.fn.fnamemodify(note, ":h"), chosen.path)
		local text = chosen.meta.title or chosen.label
		local row = vim.api.nvim_win_get_cursor(0)[1]
		vim.api.nvim_buf_set_lines(buf, row, row, false, { "", ("![%s](%s)"):format(text, href) })
		vim.api.nvim_win_set_cursor(0, { row + 2, 0 })
	end)
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

command("ExerciseNew", function()
	M.new_exercise()
end, { desc = "file a new exercise in the notebook and open it" })
command("AssignmentNew", M.new_assignment, { desc = "file a new assignment in the notebook and open it" })
command("ExerciseFind", M.find, { desc = "open an exercise from the notebook" })
command("ExerciseFromNote", M.note_exercises, { desc = "open an exercise set from this note" })
command("ExerciseEdit", M.edit_exercise, { desc = "open the exercise referenced on this line" })
command("ExerciseStatus", M.set_status, { desc = "set how far along this exercise is" })
command("ExercisePreview", M.preview_exercise, { desc = "open this exercise's page in a browser" })
command("ExerciseOpen", M.open_exercises, { desc = "open the exercise catalogue in a browser" })
command("ExerciseInsert", M.insert_reference, { desc = "reference an exercise from this note" })

vim.keymap.set("n", "<leader>zs", M.toggle, { desc = "toggle preview server" })
vim.keymap.set("n", "<leader>zp", M.preview, { desc = "preview note in browser" })
vim.keymap.set("n", "<leader>zP", M.open, { desc = "open site in browser" })

vim.keymap.set("n", "<leader>dn", M.new_drawing, { desc = "new drawing" })
vim.keymap.set("n", "<leader>de", M.edit_drawing, { desc = "edit drawing on this line" })

-- Global rather than buffer-local, unlike the typst maps in plugins/typst.lua.
-- Half of these are used from a note and half from an exercise, and a set of
-- bindings that only appears in one of the two would be the wrong half every
-- other time. Each says plainly when it is asked somewhere it cannot answer.
vim.keymap.set("n", "<leader>xn", function()
	M.new_exercise()
end, { desc = "new exercise" })
vim.keymap.set("n", "<leader>xa", M.new_assignment, { desc = "new assignment" })
vim.keymap.set("n", "<leader>xx", M.find, { desc = "open an exercise" })
vim.keymap.set("n", "<leader>xf", M.note_exercises, { desc = "exercises set from this note" })
vim.keymap.set("n", "<leader>xe", M.edit_exercise, { desc = "open exercise on this line" })
vim.keymap.set("n", "<leader>xs", M.set_status, { desc = "set exercise status" })
vim.keymap.set("n", "<leader>xp", M.preview_exercise, { desc = "preview exercise in browser" })
vim.keymap.set("n", "<leader>xo", M.open_exercises, { desc = "open exercise catalogue" })
vim.keymap.set("n", "<leader>xi", M.insert_reference, { desc = "reference an exercise here" })

-- Leaving nvim with a server still running would orphan it and hold the port.
vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		if M.running() then
			state.job:kill("sigterm")
		end
	end,
})

return M
