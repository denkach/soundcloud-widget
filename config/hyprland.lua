-- Load once from your Hyprland Lua configuration.
-- Blur settings remain inherited from your existing Hyprland theme.
hl.on("hyprland.start", function ()
    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/soundcloud-widget start")
end)

soundcloud_widget_blur_rule = hl.layer_rule({
    name = "soundcloud-widget-idle-blur",
    match = { namespace = "^soundcloud-widget$" },
    blur = true,
    ignore_alpha = 0.001,
})

function soundcloud_widget_set_active(active)
    local enabled = not active
    if soundcloud_widget_blur_rule:is_enabled() ~= enabled then
        soundcloud_widget_blur_rule:set_enabled(enabled)
    end
end
