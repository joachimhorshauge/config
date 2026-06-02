------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
hl.monitor({
	output   = "",
	mode     = "preferred",
	position = "auto",
	scale    = "auto",
})

-- TODO: Move this
hl.window_rule({
	name  = "pip-float",
	match = { title = "[Pp]icture.[Ii]n.[Pp]icture" },
	float = true,
	pin   = true,
	size  = { 640, 360 },
	move  = { "100%-660", "100%-380" }, -- bottom-right with ~20px margin
})
