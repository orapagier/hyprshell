--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

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
})

-- Match browser dialog titles exactly, so regular browser windows stay tiled.
hl.window_rule({
    name  = "float-browser-dialogs",
    match = {
        class = "(?i)^(brave-browser(-beta|-nightly)?|brave|google-chrome(-beta|-unstable)?|firefox(-esr)?|org\\.mozilla\\.firefox)$",
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
