-- Programs started once when the desktop session begins.
hl.on("hyprland.start", function()
    hl.exec_cmd('uwsm app -- "$HOME/.local/bin/start-quickshell-bar"')
    -- Hyprmonitor starts on demand through Alt+I or its application entry.
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd('python3 "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings/theme.py" --restore')
    hl.exec_cmd('python3 "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings/applications.py" --restore')
    hl.exec_cmd('sh "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/file-picker-preferences.sh"')
    -- Wallpaper (awww, successor of swww): start daemon, then set image
    hl.exec_cmd('"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpaper-start.sh"')
end)
