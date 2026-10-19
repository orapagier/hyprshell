# Fluid desktop

Hyprshell owns the desktop implementation and continues to use its existing
services, preferences, launcher, panel visibility, idle controls and Hyprlock
supervisor. Sidera/Caelestia is a visual reference, not a runtime dependency.
The spatial and effects easing values follow the expressive animation curves
visible in Sidera's animation tokens. The dashboard and lock layout are written
for Hyprshell; no Sidera QML or C++ module is imported.

Hover colors ease over 200 ms. Button shapes and menu movement use an expressive
350 ms curve, and presses provide a small scale response. Menus arrive from their
actual panel edge. The existing Reduce desktop motion preference disables these
animations. Panel geometry, input targets and hover opening/closing delays remain
unchanged.

Four 20 px black corner cutouts round each output. They have empty input masks,
no edge strips and no exclusive zone; rectangular workspace dimensions are
unchanged. The very tips of the display are visually masked, including over
fullscreen applications. The ordinary configured Hyprpane/dock reservations
continue to apply.

Super+D opens the dashboard on the focused monitor, even when Hyprpane is hidden.
Escape, Close or a click outside dismisses it. Dashboard, Media and Performance
tabs show the existing calendar, MPRIS playback and local CPU/memory/uptime data.
Quick actions open the existing Wi-Fi, audio, notification and power menus,
Settings and lock screen. Resource sampling runs every two seconds only while
the dashboard is open; the first CPU sample waits for a second counter reading.
The layout wraps and scrolls on smaller displays. No weather network service or
location setting is introduced.

The lock theme has a large accent clock, date, user icon/name, rounded password
field and a blurred screenshot background. Hyprlock continues to own password
authentication and the session lock, including existing failure and resume
recovery behavior. Super+L and all idle/sleep locking paths retain that backend.

`hyprshell-activate` verifies access to Hyprland and the session bus, checkpoints
the main configuration, reloads it and stops only Sidera's shell instance before
starting Hyprshell. If startup fails it restores the configuration and restarts
Sidera when it was running. It does not log out, reboot or alter Sidera's files.
The main configuration is switched only when this command can access the desktop.
When no native wallpaper daemon is running, activation starts awww and uses the
current Sidera wallpaper file when available, otherwise Hyprshell's default.
An existing awww session is retained. Recovery stops only a daemon started by
this activation; no Caelestia command is needed to display the wallpaper.
