-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
hl.on("hyprland.start", function () 
    hl.exec_cmd("swaync")
    hl.exec_cmd("awww-daemon")
		hl.exec_cmd("awww img /home/joggefar/dotfiles/media/wallpaper/wallpaper_everforest_1.jpg")
end)
