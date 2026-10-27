# Fluid desktop

Hyprshell owns the desktop implementation and continues to use its existing
services, preferences, launcher, panel visibility, idle controls and Hyprlock
supervisor. The dashboard and lock layout use native Hyprshell components.

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

Super+D or the bottom-left hot corner opens the dashboard. Escape, leaving the
drawer or a click outside dismisses it. System Info shows identity, RAM capacity,
uptime and estimated OS age. A resource card below OS age shows CPU usage, RAM
used/total and free space on the root filesystem, with usage bars. A lightweight
helper samples every two seconds while the left dashboard is open and exits on
close; it does not scan processes or run for the right activity drawer. System
identity is read once per opening. Settings and Lock remain available; the shortcuts card and
embedded calendar have been removed to make room for weather. The standalone
calendar menu remains available elsewhere in the shell.

Weather uses a short-lived Rust helper, with system curl for HTTPS, and displays
cached data immediately. Opening the dashboard refreshes data only when the cache
is older than 15 minutes. There is no weather timer or background service. City
search defaults to the Philippines and includes province/region details; manual
coordinates cover places missing from GeoNames. Weather → Change city saves the selected
place in `hyprshell/weather.json`, retained by updates and explicit GitHub sync.
Cached forecasts stay local. The weather-first layout uses a large temperature,
static vector condition illustration, grouped readings, a rounded next-three-hours
forecast card and aligned device details.
The city editor replaces the forecast while editing, with keyboard focus on
search. Content resizes smoothly, respecting Reduce desktop motion; narrow
layouts stack and scroll. The card shows conditions, temperature/feels-like,
humidity, wind/gusts, rainfall, today's high/low and rain chance, sunrise/sunset
and the data timestamp. Offline failures retain the previous weather and mark it
as cached. The layout wraps and scrolls on smaller displays. See
[the weather helper](../apps/hyprweather-rs/README.md) for build and validation.

The lock theme has a large accent clock, date, user icon/name, rounded password
field and a blurred screenshot background. Hyprlock continues to own password
authentication and the session lock, including existing failure and resume
recovery behavior. Super+L and all idle/sleep locking paths retain that backend.

`hyprshell-activate` verifies access to Hyprland and the session bus, checkpoints
the main configuration, reloads it and starts Hyprshell. If startup fails it
restores the previous configuration. When no native wallpaper daemon is running,
activation starts awww with the default wallpaper. An existing awww session is
retained. Recovery stops only a daemon started by this activation.
