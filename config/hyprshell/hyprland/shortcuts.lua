-- Default shortcuts; Hyprshell Settings customizations apply afterward.
return function(programs)
local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(programs.terminal), { description = "Open terminal" })
local closeWindowBind = hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { description = "Close window" })
-- closeWindowBind:set_enabled(false)
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("python3 \"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings/session.py\" --logout"), { description = "Log out to login screen" })
hl.bind(mainMod .. " + M", hl.dsp.window.fullscreen({ mode = "maximized" }), { description = "Maximize window" })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(programs.fileManager), { description = "Open file manager" })
hl.bind(mainMod .. " + ALT + V", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating window" })
-- Copy/paste use native application shortcuts. Kitty maps Ctrl+C/Ctrl+V
-- directly, avoiding stuck synthetic keys from send_shortcut forwarding.

-- Quickshell handles launcher toggling and outside clicks natively.
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd(programs.menu), { release = true, description = "Toggle application launcher" })
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" displays'), { description = "Duplicate or extend displays" })
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" hyprview'), { description = "Project active window in Hyprview" })
hl.bind(mainMod .. " + SHIFT + V", function()
    hl.exec_cmd('"' .. os.getenv("HOME") .. '/.local/bin/hyprshell-shortcut" hyprview-close')
end, { description = "Close Hyprview from any screen" })
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.window.pseudo(), { description = "Toggle pseudo tiling" })
hl.bind(mainMod .. " + CTRL + F", hl.dsp.exec_cmd('python3 "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings/behavior.py" --toggle-workspace floating'), { description = "Toggle auto floating on current workspace" })
hl.bind(mainMod .. " + CTRL + S", hl.dsp.exec_cmd('python3 "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings/behavior.py" --toggle-workspace pseudotiled'), { description = "Toggle auto pseudotiling on current workspace" })
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"), { description = "Toggle split direction" })    -- dwindle only

hl.bind("SUPER + K", hl.dsp.exec_cmd('"$HOME/.local/bin/keybindings-launcher"'), { description = "Show searchable keybindings" })

-- Hyprshell keyboard access, including when Hyprpane is hidden.
hl.bind("ALT + T", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" topbar'), { description = "Toggle Hyprpane on current workspace" })
hl.bind("ALT + Z", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" hyprbar'), { description = "Toggle Hyprbar on current workspace" })
hl.bind("ALT + D", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" hyprdock'), { description = "Toggle Hyprdock on current workspace" })
hl.bind("ALT + C", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" calendar'), { description = "Toggle calendar" })
hl.bind("ALT + S", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" settings'), { description = "Open Hyprshell Settings" })
hl.bind("ALT + N", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" notifications'), { description = "Toggle notifications" })
hl.bind("ALT + A", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" audio'), { description = "Toggle audio volume" })
hl.bind("ALT + W", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" wifi'), { description = "Toggle Wi-Fi" })
hl.bind("ALT + V", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" bluetooth'), { description = "Toggle Bluetooth" })
hl.bind("ALT + B", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" battery'), { description = "Toggle battery" })
hl.bind("ALT + P", hl.dsp.exec_cmd('"$HOME/.local/bin/hyprshell-shortcut" power'), { description = "Toggle power options" })
hl.bind("SUPER + L", hl.dsp.exec_cmd('python3 "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings/backend.py" --lock'), { description = "Lock screen" })
-- Direct power actions: hold Super+Alt and press the action letter.
hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd('python3 "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings/backend.py" --lock'), { description = "Lock screen" })
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd("systemctl suspend"), { description = "Sleep" })
hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd("systemctl reboot"), { description = "Reboot" })
hl.bind("SUPER + ALT + X", hl.dsp.exec_cmd("systemctl poweroff"), { description = "Shutdown" })
hl.bind("SUPER + ALT + O", hl.dsp.exec_cmd('python3 "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings/session.py" --logout'), { description = "Log out to login screen" })

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }), { description = "Focus left" })
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Focus right" })
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }), { description = "Focus up" })
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }), { description = "Focus down" })

-- Swap the active tiled window with its directional neighbor, preserving the layout.
-- mainMod + SHIFT + arrow keys
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.swap({ direction = "left" }),  { description = "Swap window left" })
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.swap({ direction = "right" }), { description = "Swap window right" })
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.swap({ direction = "up" }),    { description = "Swap window up" })
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.swap({ direction = "down" }),  { description = "Swap window down" })

-- Move and retile the active window with mainMod + ALT + arrow keys.
hl.bind(mainMod .. " + ALT + left", hl.dsp.window.move({ direction = "left" }), { description = "Move window left" })
hl.bind(mainMod .. " + ALT + right", hl.dsp.window.move({ direction = "right" }), { description = "Move window right" })
hl.bind(mainMod .. " + ALT + up", hl.dsp.window.move({ direction = "up" }), { description = "Move window up" })
hl.bind(mainMod .. " + ALT + down", hl.dsp.window.move({ direction = "down" }), { description = "Move window down" })

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}), { description = "Switch to workspace " .. i })
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"), { description = "Toggle scratchpad" })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), { description = "Move window to scratchpad" })

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Next workspace" })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Previous workspace" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Drag window" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { description = "Resize window", mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
-- Volume / brightness keys without needing Fn (with Fn they send XF86* symbols, already bound below)
hl.bind("F3", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { description = "Increase volume", repeating = true })
hl.bind("F2", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { repeating = true, description = "Decrease volume" })
hl.bind("F4", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { repeating = true, description = "Toggle speaker mute" })
hl.bind("F1", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { repeating = true, description = "Toggle microphone mute" })
hl.bind("F7", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { repeating = true, description = "Increase brightness" })
hl.bind("F6", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { repeating = true, description = "Decrease brightness" })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { description = "Increase volume", locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true, description = "Decrease volume" })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true, description = "Toggle speaker mute" })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true, description = "Toggle microphone mute" })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true, description = "Increase brightness" })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true, description = "Decrease brightness" })

-- Screenshot region snipping tool: Print opens the region selector, then edit in swappy
hl.bind("Print", hl.dsp.exec_cmd('grim -g "$(slurp)" - | swappy -f -'), { description = "Capture screenshot region" })
-- This keyboard's Print key emits KEY_INSERT, so bind it as well
hl.bind("Insert", hl.dsp.exec_cmd('grim -g "$(slurp)" - | swappy -f -'), { description = "Capture screenshot region" })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { description = "Play / pause media", locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { description = "Play / pause media", locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Previous track" })

hl.bind("SUPER + B", hl.dsp.exec_cmd(programs.browser), { description = "Open browser" })

-- Wallpapers: SUPER+W = next, SUPER+SHIFT+W = previous (cycles ~/Pictures/Wallpapers)
hl.bind("SUPER + W", hl.dsp.exec_cmd('"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpaper-cycle.sh" next'), { description = "Next wallpaper" })
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd('"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpaper-cycle.sh" prev'), { description = "Previous wallpaper" })

-- Minimize (LIFO stack): SUPER+H hides focused window,
-- SUPER+SHIFT+H restores them one by one, most recent first
local minimizedStack = {}

hl.bind("SUPER + H", function()
    local win = hl.get_active_window()
    if win == nil then return end
    table.insert(minimizedStack, win.address)
    hl.dispatch(hl.dsp.window.move({ window = win, workspace = "special:minimized" }))
end, { description = "Minimize window" })

hl.bind("SUPER + SHIFT + H", function()
    while #minimizedStack > 0 do
        local addr = table.remove(minimizedStack)
        if hl.get_window("address:" .. addr) ~= nil then
            local wsid = hl.get_active_monitor().active_workspace.id
            hl.dispatch(hl.dsp.window.move({ window = "address:" .. addr, workspace = wsid }))
            hl.dispatch(hl.dsp.focus({ window = "address:" .. addr }))
            return
        end
        -- window was closed while minimized, drop it and try the next one
    end
    -- nothing tracked left: toggle the special workspace as a fallback
    hl.dispatch(hl.dsp.workspace.toggle_special("minimized"))
end, { description = "Restore minimized window" })
end
