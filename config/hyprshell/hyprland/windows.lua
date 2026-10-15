--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

-- ONLYOFFICE uses the presentation's own window for its fullscreen slideshow.
-- Route it on entry, then return the editor when the slideshow ends. Mirrored
-- outputs are not independent presentation destinations.
local presentationOrigins = {}
local presentationMoves = {}
local function routePresentation(w)
    if presentationMoves[w.address] then return end
    local origin = presentationOrigins[w.address]
    if w.fullscreen ~= 2 then
        if origin then
            presentationOrigins[w.address] = nil
            local monitor = hl.get_monitor(origin.monitor)
            if monitor and not monitor.is_mirror then
                local workspace = hl.get_workspace(origin.workspace)
                if workspace and workspace.monitor and workspace.monitor.name == origin.monitor then
                    hl.dispatch(hl.dsp.window.move({ window = w, workspace = workspace, follow = true }))
                else
                    hl.dispatch(hl.dsp.window.move({ window = w, monitor = monitor, follow = true }))
                end
            end
        end
        return
    end
    if origin or w.class ~= "ONLYOFFICE" or w.fullscreen_client ~= 2 then return end
    local title = (w.title or ""):lower()
    if not (title:match("%.pptx%s") or title:match("%.pptx$")) then return end
    local monitors = {}
    for _, monitor in ipairs(hl.get_monitors()) do
        if not monitor.is_mirror then table.insert(monitors, monitor) end
    end
    if #monitors < 2 or not w.monitor or not w.workspace then return end
    -- Prefer HDMI projectors, then other external outputs; never hardcode a port.
    local function rank(m)
        if m.name:match("^HDMI") then return 1 end
        if m.name:match("^eDP") or m.name:match("^LVDS") or m.name:match("^DSI") then return 3 end
        return 2
    end
    table.sort(monitors, function(a, b)
        if rank(a) == rank(b) then return a.name < b.name end
        return rank(a) < rank(b)
    end)
    local target = monitors[1]
    if rank(target) == 3 or target.name == w.monitor.name then return end
    presentationOrigins[w.address] = { monitor = w.monitor.name, workspace = w.workspace.id }
    -- Let ONLYOFFICE finish its initial X11 fullscreen geometry request before
    -- moving it. Re-enter compositor fullscreen on the destination to recompute
    -- its position and size, keeping the client in slideshow mode throughout.
    local address, monitorName = w.address, target.name
    presentationMoves[address] = hl.timer(function()
        local current = hl.get_window("address:" .. address)
        local destination = hl.get_monitor(monitorName)
        if current and current.fullscreen_client == 2 and destination and not destination.is_mirror then
            hl.dispatch(hl.dsp.window.fullscreen_state({ window = current, internal = 0, client = 2, action = "set" }))
            hl.dispatch(hl.dsp.window.move({ window = current, monitor = destination, follow = false }))
            hl.dispatch(hl.dsp.window.fullscreen_state({ window = current, internal = 2, client = 2, action = "set" }))
        else
            presentationOrigins[address] = nil
        end
        presentationMoves[address] = nil
    end, { timeout = 200, type = "oneshot" })
end
hl.on("window.fullscreen", routePresentation)
hl.on("window.open", routePresentation)
hl.on("window.title", routePresentation)
hl.on("window.close", function(w)
    presentationOrigins[w.address] = nil
    local timer = presentationMoves[w.address]
    if timer then timer:set_enabled(false) end
    presentationMoves[w.address] = nil
end)
local function routeOpenPresentations()
    for _, w in ipairs(hl.get_windows()) do routePresentation(w) end
end
hl.on("monitor.layout_changed", routeOpenPresentations)
hl.on("config.reloaded", routeOpenPresentations)

-- Settings starts floating; Super+V can still toggle it into the tiling layout.
-- Center horizontally and lift it 40px above the vertical midpoint.
hl.window_rule({
    name = "hyprshell-settings-placement",
    match = { initial_title = "^Hyprshell Settings$" },
    float = true,
    size = { "min(1180,monitor_w*0.9)", "monitor_h*0.75" },
    move = { "(monitor_w-min(1180,monitor_w*0.9))/2", "max(48,monitor_h*0.125-40)" },
})

-- Float dialogs without changing the default tiling of normal app windows.
-- Modal is an app-provided dialog flag, not a window-size heuristic.
hl.window_rule({
    name  = "float-modal-dialogs",
    match = { modal = true },
    float = true,
    center = true,
})

-- Cross-app fallback for dialogs that omit the modal/transient hints.
-- Match complete titles so document titles containing these words still tile.
local dialogTitles = {
    "Open", "Open File", "Open Files", "Open Folder", "Open Directory",
    "Save", "Save As", "Save File", "Save a File",
    "Select File", "Select Files", "Select Folder", "Select Directory",
    "Choose File", "Choose Files", "Choose Folder", "Choose Directory",
    "Preferences", "Settings", "Properties", "About",
    "Print", "Print Preview", "Page Setup",
    "Export", "Export File", "Import", "Import File",
    "Confirm", "Confirmation", "Authentication Required", "Authenticate",
    "Password Required", "Enter Password", "Picture-in-Picture",
}
hl.window_rule({
    name = "float-app-dialogs",
    match = { title = "(?i)^(" .. table.concat(dialogTitles, "|") .. ")$" },
    float = true,
    center = true,
})

-- Popups must float at map time, before entering the tiling layout.
-- Hyprland detects app-provided modal/transient/type hints automatically,
-- so browser popups keep their native "pop-up" role independent of their
-- eventual page title. Do not float on window.title: that causes a visible
-- tile-then-float jump.

-- Some Thunar dialogs do not advertise themselves as modal.
hl.window_rule({
    name  = "float-thunar-dialogs",
    match = {
        class = "(?i)^(thunar|org\\.xfce\\.thunar)$",
        title = '^((Rename "[^"]*")|(Create (New )?(Folder|File))|(.* - Properties)|(Confirm to replace files)|(Replace the (link|folder|file) in ".*")|(File Operation Progress))$',
    },
    float = true,
    center = true,
})

-- File chooser portal windows are dialogs, even without a modal flag.
hl.window_rule({
    name  = "float-file-chooser-portals",
    match = { class = "^(xdg-desktop-portal-(gtk|gnome|kde)|org\\.freedesktop\\.impl\\.portal\\.desktop\\.(gtk|gnome|kde))$" },
    float = true,
    center = true,
    size = { "min(860,monitor_w*0.9)", "min(560,monitor_h*0.8)" },
})

-- Keep app-owned file pickers compact too; ordinary settings dialogs keep their size.
local filePickerTitles = {
    "Open", "Open File", "Open Files", "Open Folder", "Open Directory",
    "Save", "Save As", "Save File", "Save a File",
    "Select File", "Select Files", "Select Folder", "Select Directory",
    "Choose File", "Choose Files", "Choose Folder", "Choose Directory",
    "Export File", "Import File",
}
hl.window_rule({
    name = "compact-file-pickers",
    match = { initial_title = "(?i)^(" .. table.concat(filePickerTitles, "|") .. ")$" },
    float = true,
    center = true,
    size = { "min(860,monitor_w*0.9)", "min(560,monitor_h*0.8)" },
})

-- Match browser dialog titles exactly, so regular browser windows stay tiled.
hl.window_rule({
    name  = "float-browser-dialogs",
    match = {
        class = "(?i)^(brave-browser(-beta|-nightly)?|brave|chromium(-browser)?|google-chrome(-beta|-unstable)?|firefox(-esr)?|org\\.mozilla\\.firefox)$",
        title = "^(Open|Open File|Open Files|Save|Save As|Save File|Select File|Select Folder|Choose File|Choose Files|Choose Folder|Picture-in-Picture)$",
    },
    float = true,
    center = true,
})

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Native Hyprshell bar: frosted glass and slide animation.
hl.layer_rule({
    name = "hyprshell-glass",
    match = { namespace = "hyprshell" },
    blur = true,
    ignore_alpha = 0.05,
    animation = "slide",
})

-- Frosted shortcut overlay; transparent space around the card stays clear.
hl.layer_rule({
    name = "hyprshell-keybindings-glass",
    match = { namespace = "^hyprshell-keybindings$" },
    blur = true,
    ignore_alpha = 0.05,
})

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})
