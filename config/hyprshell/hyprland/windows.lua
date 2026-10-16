--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

-- Normal slideshows stay on the laptop and PresentationView copies their
-- window to HDMI. Only native Presenter View needs its audience window moved.
local presentationOrigins = {}
local presentationMoves = {}
local presentationRestores = {}
local function isPresentation(w)
    local title = (w.title or ""):lower()
    return w.class == "ONLYOFFICE" and (title:match("%.pptx%s") or title:match("%.pptx$"))
end
local function nativePresenter(slideshow)
    for _, other in ipairs(hl.get_windows()) do
        local title = (other.title or ""):lower()
        if other.address ~= slideshow.address and other.class == "ONLYOFFICE"
            -- accepts_input is also false while the slideshow covers controls.
            -- Neither it nor visible identifies whether the presenter exists.
            and other.pid == slideshow.pid
            and other.mapped and not other.hidden and other.fullscreen_client ~= 2
            and (title:find("presenter", 1, true) or title:find("reporter", 1, true)
                or title:find("speaker", 1, true) or title == "onlyoffice" or title == "") then
            return other
        end
    end
end
local function restorePresentationEditor(pid)
    if presentationRestores[pid] then presentationRestores[pid]:set_enabled(false) end
    -- ONLYOFFICE unmaps its editor while native Presenter View is open and
    -- remaps it after destroying the two presentation windows.
    presentationRestores[pid] = hl.timer(function()
        presentationRestores[pid] = nil
        local active = hl.get_active_window()
        if active and active.pid ~= pid then return end
        local editor
        for _, candidate in ipairs(hl.get_windows()) do
            if candidate.pid == pid and isPresentation(candidate) and candidate.mapped and not candidate.hidden then
                if candidate.fullscreen_client == 2 then return end
                editor = candidate
            end
        end
        if editor then
            hl.dispatch(hl.dsp.focus({ window = "address:" .. editor.address }))
            hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = editor }))
        end
    end, { timeout = 250, type = "oneshot" })
end
local function routePresentation(w)
    if presentationMoves[w.address] then return end
    local origin = presentationOrigins[w.address]
    if w.fullscreen ~= 2 then
        if origin then
            presentationOrigins[w.address] = nil
            restorePresentationEditor(origin.pid)
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
    if origin or not isPresentation(w) or w.fullscreen_client ~= 2 then return end
    local presenter = nativePresenter(w)
    if not presenter then return end
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
    local controlsMonitor = monitors[#monitors]
    if rank(target) == 3 then return end
    presentationOrigins[w.address] = { monitor = w.monitor.name, workspace = w.workspace.id,
        pid = w.pid, presenter = presenter.address }
    -- Let the two native X11 windows finish mapping. Move the audience window
    -- directly, keeping fullscreen intact, then give controls the laptop screen.
    local address, monitorName = w.address, target.name
    local presenterAddress, controlsName = presenter.address, controlsMonitor.name
    presentationMoves[address] = hl.timer(function()
        local current = hl.get_window("address:" .. address)
        local controls = hl.get_window("address:" .. presenterAddress)
        local destination = hl.get_monitor(monitorName)
        local controlsDestination = hl.get_monitor(controlsName)
        if current and current.fullscreen_client == 2 and controls and controls.mapped
            and current.mapped and destination and not destination.is_mirror
            and controlsDestination and not controlsDestination.is_mirror then
            if not current.monitor or current.monitor.name ~= destination.name then
                hl.dispatch(hl.dsp.window.move({ window = current, monitor = destination, follow = false }))
            end
            if not controls.monitor or controls.monitor.name ~= controlsDestination.name then
                hl.dispatch(hl.dsp.window.move({ window = controls, monitor = controlsDestination, follow = false }))
            end
            -- Internal fullscreen supplies the full monitor size without
            -- asking ONLYOFFICE to turn its controls into another slideshow.
            hl.dispatch(hl.dsp.window.fullscreen_state({ window = controls, internal = 2, client = 0, action = "set" }))
            hl.dispatch(hl.dsp.focus({ window = "address:" .. controls.address }))
        else
            presentationOrigins[address] = nil
        end
        presentationMoves[address] = nil
    end, { timeout = 200, type = "oneshot" })
end
hl.on("window.fullscreen", routePresentation)
hl.on("window.close", function(w)
    local origin = presentationOrigins[w.address]
    if origin then restorePresentationEditor(origin.pid) end
    for _, session in pairs(presentationOrigins) do
        if session.presenter == w.address then restorePresentationEditor(session.pid) end
    end
    presentationOrigins[w.address] = nil
    local timer = presentationMoves[w.address]
    if timer then timer:set_enabled(false) end
    presentationMoves[w.address] = nil
end)
local function routeOpenPresentations()
    for _, w in ipairs(hl.get_windows()) do routePresentation(w) end
end
-- The native presenter may map after the audience window enters fullscreen.
hl.on("window.open", routeOpenPresentations)
hl.on("window.title", routeOpenPresentations)
hl.on("monitor.layout_changed", routeOpenPresentations)
hl.on("config.reloaded", routeOpenPresentations)

-- Hyprview is a normal movable, resizable window, floating on first open.
hl.window_rule({
    name = "hyprshell-hyprview-placement",
    match = { initial_title = "^Hyprview$" },
    float = true,
    decorate = false,
    border_size = 0,
    rounding = 0,
    no_shadow = true,
    center = true,
    size = { "min(960,monitor_w*0.85)", "min(600,monitor_h*0.8)" },
})

-- Settings starts floating; Super+Alt+V can still toggle it into the tiling layout.
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
