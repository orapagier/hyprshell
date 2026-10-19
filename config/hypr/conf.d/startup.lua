-- Start Sidera once; keep authentication support independent of the shell.
hl.on("hyprland.start", function()
    hl.exec_cmd('uwsm app -- caelestia-shell --no-duplicate --daemonize')
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
end)
