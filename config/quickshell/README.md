# Native Quickshell panel

**hyprbar** is Hyprshell's top bar, also called the bar, topbar, or panel here.

The panel, launcher, calendar, audio, Wi-Fi, Bluetooth, notification inbox,
power menu, media display, and status bindings are QML/JavaScript components.
The desktop service bindings and menus are native QML. Python helpers handle
settings, shortcut edits, cleanup, and GitHub sync.

The QML files live directly in `~/.config/quickshell/`, with `shell.qml` as
the default entry point. Its explicit ShellId identifies Hyprshell's persistent
notification history.

## Hyprview

Focus an application and press **Super+V** to show a live, view-only copy in
Hyprview. Press it from another application to replace the source in the same
viewer. Changing focus alone keeps the selected source. The viewer contains only
the projected image, with no header, picker, footer, buttons or window decorations.
Hyprview opens fullscreen on an enabled external display, preferring HDMI, then
other outputs by name. The built-in panel (or first screen on a desktop) remains
the primary display. Mirrored and disabled outputs are skipped. Connecting an
external display while the viewer is open moves the projection there automatically;
disconnecting it returns the viewer to windowed mode. With one screen, Hyprview
starts floating. The source image stretches to fill the viewer or projector without
black bars; different source and output proportions can distort the image.
Opening Hyprview does not request keyboard focus or pull the pointer to its output;
external projection uses a screen-filling layer surface instead of moving a
focused window between monitors. The capture omits the source cursor. Click the
viewer to focus it for its local keys.
**Super+Shift+V** closes Hyprview from any screen, regardless of keyboard focus.
Inside the viewer, **F11** toggles fullscreen; **Escape** leaves fullscreen
first, then closes. Pressing Super+V while Hyprview itself is focused also closes
it. Closing releases capture; after closing a source, focus another application
and press Super+V to project it.
Control the application through its original window. Super+Alt+V still toggles
floating for any window. The shortcut is searchable with Super+K and editable in
Settings → Keybindings.

`Hyprview.qml` uses Quickshell's native `ScreencopyView` and the compositor's
window capture protocol, with no recorder or virtual monitor required. Windows
without a capture handle show a message. A stopped stream can be retried by
pressing Super+V from the source again. Native offscreen checks cover selection,
switching, recursive-capture prevention, fullscreen targeting, full-window canvas,
fill sizing and resizing, close/reopen, hotplug, mirrored/disabled outputs and external projection
without a toplevel window. Real video and pointer behavior need a live Hyprland check.

The styling uses 32px panel height, 28px pills, and 5px top / 10px side
margins, transparent background, wallpaper-tinted glass pills, DejaVu Sans / GoMono
Nerd Font, and a configurable module order. The `hyprshell` layer namespace
connects the panel to compositor blur and animation rules.

Each pill samples the wallpaper directly underneath its current position.
`WallpaperWatcher.qml` queries awww every two seconds, independently identifying
the image on each output. `WallpaperColors.qml` matches the default centered
crop and samples only the 32px strip behind the panel, with no screen capture.
Item movement and screen resizing update the sampled region automatically.
`AdaptiveColors.js` blends local wallpaper hues into the existing status colors,
chooses light or dark surfaces, and adjusts foreground colors to maintain text
contrast against the sampled region (at least 4.5:1, including hover, selection,
and the glass highlight). Glass starts at 22% opacity so the compositor blur
shows through. Only mixed or difficult wallpaper regions increase the tint's
opacity, using the darkest and lightest sampled pixels to protect readability.
Notification badges, workspace indicators, and media bars use the same adaptive
foreground; application tray artwork retains its original colors on an adaptive
surface. Missing wallpaper data uses a readable dark fallback. This setup follows
the centered `--resize crop` mode used by the wallpaper cycle script; custom
resize modes, crop gravities, and animated wallpaper frames are not tracked.

## Native services

- Workspaces: `Quickshell.Hyprland`.
- Audio sliders, microphone mute, output selection: `Quickshell.Services.Pipewire`.
  The bar uses Android-style Material speaker icons and a headset icon for
  active wired/USB/Bluetooth headphones. A read-only `pactl` subscription
  tracks jack and output-port changes; volume control remains native.
- Media metadata: `Quickshell.Services.Mpris`.
- Output animation: twelve logarithmic FFT bands from the current speaker's
  output monitor, updated every 16 ms. Rounded bars expand about their centers,
  with fast attacks and a smooth release. A small C helper uses libpulse-simple
  and FFTW. Setup compiles it into `helpers/audio-spectrum` in the installed
  Quickshell directory (requires `cc` and the two development libraries).
  It stops when playback becomes inactive. Output-device changes reconnect the monitor.
  The topbar opens only the output monitor; `PwNodePeakMonitor` still detects non-MPRIS playback.
  Output link groups are bound with `PwObjectTracker` before checking their active
  state, so players such as mpv can show the spectrum without an MPRIS plugin.
- Settings microphone test: the same FFT helper and `AudioSpectrumBars.qml`
  renderer show twelve live input bands. An explicit `--source` argument selects
  the microphone only after starting the test. Muting flattens the bars immediately;
  stop, page navigation, or device changes close capture. A quiet-input floor and
  DC removal keep the microphone visualizer still without audible input.
- Network status, scanning, connections and passwords: `Quickshell.Networking`.
- Bluetooth status, scanning and connections: `Quickshell.Bluetooth`.
  `bluetoothctl` supplies the BlueZ pairing agent; the prompt and PIN UI are QML.
- Battery: `Quickshell.Services.UPower`, including a hover menu with charge,
  charging status, time estimates, health, power draw, and energy capacity.
  Full-charge and original design capacities in mAh are read from the
  battery's Linux power-supply data and refreshed every minute.
  A small battery-care card recommends plugging in around 20% and considering
  unplugging or using a charge limit around 80%, based on actual AC-power
  status. It treats 20–80% as a flexible everyday target, allows full charges
  when needed, and explains that a charge limit avoids repeated unplugging.
- Notification capture and actions: native `NotificationServer`.
- Launcher: native `DesktopEntries` and `DesktopEntry.execute()`.

The bell is a separate, always-present glyph. Its unread count is attached to
the glyph's upper-right corner, independently of the count's width. The Arch
logo has no background pill: the full Arch vector silhouette has a translucent
gradient and fine reflective edges, with explicit space around both legs and
vertical alignment independent of font metrics. The active workspace has an
emphasized purple glass fill and border; inactive workspaces use neutral gray
tones without an underline. The media pill uses a Loader that destroys its entire contents and
background when playback is inactive, even if stale metadata remains.

Hover over the launcher, clock, notifications, audio, Wi-Fi, Bluetooth, battery, or
power icon to open its menu. Tooltips are disabled throughout the bar. Each
menu is aligned to the right edge, except the calendar which is centered
beneath the clock and the launcher which is aligned to the left beneath the Arch logo.
All menus have a curved glass funnel tapering to a sharp point at their icon and retain
a matching accent and a short opening animation.
Application rows include 22px icons next to their names. `AppIcons.qml` uses
the platform icon theme first, then indexes installed hicolor app icons and
pixmaps through Qt's folder models. The installed Pop theme provides general
category icons, and entries without usable artwork show a generic app icon.
The popup keeps a stable surface and allows the bar to receive
pointer input, preventing hover flicker during opening and switching.
The last menu's anchor, alignment, and contents remain in place until its
closing fade finishes, so the funnel cannot stretch across the bar on exit.
Moving into the menu keeps it open;
moving away closes it after a brief grace period. Hovering another icon
switches menus. Click an icon to keep its menu open until a second click,
an outside click, or Escape. Sound and microphone sliders support dragging
and clicking the track.

Opening a popdown with a keyboard shortcut moves the pointer to its header
and lets it close when the pointer leaves, whether the topbar is visible or
hidden. With the topbar visible, the popdown keeps its usual position and
funnel connection; with it hidden, the popdown appears centered.

## Activate the native notification handler

Run once in a Hyprland desktop terminal:

```sh
~/.config/quickshell/install-and-activate.sh
```

This restarts Hyprshell and verifies the panels and notification service.
Notifications are stored with Quickshell FileView.

Click a notification to expand its full title and body; click its text again
to collapse it. Expanded text wraps without a character limit, and the list
scrolls vertically to the end of long messages. The × at the upper right of
an expanded notification dismisses it.
The inbox preserves the text supplied by each application. If a sender cuts
its text before sending it (for example, the saved Kitty titles that already
end with an ellipsis at 200 characters), changing the inbox cannot recover
the omitted text; the sender must supply the complete message.

The application launcher opens the native QML launcher and retries shell
startup if needed.

The running Quickshell instance watches these files and reloads configuration
changes automatically. Desktop activation requires access to the live Wayland,
Hyprland, PipeWire, and D-Bus session. Offscreen checks cover components and
menu rendering without those sockets.

Notification content uses the same 18px popover margins as other menus.
Wi-Fi and Bluetooth device rows stay 36px high and fit the available width;
long names elide instead of widening their menus. Workspace buttons sit slightly
closer to the Arch logo while retaining a visible gap.

## Checks

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  /usr/lib/qt6/bin/qmltestrunner -input ~/.config/quickshell/tests
python3 ~/.config/quickshell/tests/test_spectrum.py
```

Synthetic audio checks verify bass/mid/treble separation, fast note attacks,
quieter passages, smooth decay to silence, and monitor-only input selection.
An offscreen native check covers Process-to-QML frame delivery, pause/resume,
and output changes without using the desktop audio socket.
QML checks verify independent bar heights and movement at both ends.
The QML regression checks cover an absent notification data source, zero and
nonzero unread counts, active playback, stopped playback with stale metadata,
and missing media data, plus notification expansion/collapse, the corner
dismiss button, and scrolling to the final line of a message over 80,000
characters long. They also cover hovering all eight menus, switching icons,
crossing the funnel into the menu, clicking menu controls, closing on exit,
keeping a clicked menu open, connector positioning after a screen resize,
and dragging both audio sliders inside the popover. The native service/menu validation entry is
`Validate.qml`; use a temporary XDG_STATE_HOME when running it because it
instantiates a test inbox. `Preview.qml` renders the bar with sample statuses.

Wallpaper checks cover separate light/dark/colored image regions, horizontal
and vertical center cropping, item and ancestor movement, missing images,
awww output parsing and path escaping, and contrast over varied backgrounds
for normal, hover, and selected states.

Startup output: `~/.local/state/quickshell/bar.log`.

Installer backups live under `~/.local/state/hyprshell/backups/`.
