-- Load once from your Hyprland Lua configuration.
-- Blur settings remain inherited from your existing Hyprland theme.
hl.on("hyprland.start", function ()
    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/soundcloud-widget start")
end)

soundcloud_widget_blur_rule = hl.layer_rule({
    name = "soundcloud-widget-idle-blur",
    match = { namespace = "^soundcloud-widget-blur$" },
    blur = true,
    ignore_alpha = 0.001,
})

-- Foreground stays sharp; only the separate backdrop has native blur.
soundcloud_widget_foreground_rule = hl.layer_rule({
    name = "soundcloud-widget-sharp-foreground",
    match = { namespace = "^soundcloud-widget$" },
    blur = false,
})

-- Clear the legacy on/off hover hook after upgrading the configuration.
soundcloud_widget_set_active = nil
