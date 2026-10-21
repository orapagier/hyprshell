# Hyprmatrix

A separate Rust digital-rain desktop effect for Hyprland. It uses a native
Wayland bottom-layer surface above the wallpaper and beneath application windows.
It has no title bar, borders, dock entry or taskbar window.

## Use

Launch **Hyprmatrix** from the app launcher to start it and open settings, or run
`~/.local/bin/hyprmatrix` for rain alone. Right-click the invisible 44 × 44 logical
pixel area at the upper-right of the effect to toggle settings. Other clicks pass
through to the desktop. The settings panel accepts input only within its bounds;
close it using its Close settings row or right-click the corner again. Ordinary
application windows and panels remain above the effect and can cover the hotspot.
`hyprmatrix --settings` opens the menu without finding the corner.

Settings rows use their left half to decrease a value and right half to increase
it. Placement toggles full-monitor coverage and a smaller desktop region. Region
width, height and horizontal/vertical position are adjustable without creating a
floating window. Rain opacity and black background opacity are independent;
background zero leaves the wallpaper fully visible. Changes save immediately to
`${XDG_CONFIG_HOME:-~/.config}/hyprmatrix/config.toml`. A failed save keeps the old
settings and reports the error inside the menu.

Super with the left mouse button drags the region when the press starts over it;
the same combination still drags windows when it starts anywhere else. Dragging
the settings panel moves the region as well. Rain visibility is remembered per
workspace: Alt+M toggles the active workspace, `hyprmatrix --toggle-workspace`
does the same from a shell, and the app keeps running while a workspace hides the
effect. Toggles are stored under `[workspace_overrides]` in the config;
workspaces without an entry keep rain off, and a fresh start enables the launch
workspace once so the first launch already shows rain.

Commands:

```sh
hyprmatrix --settings
hyprmatrix --fullscreen
hyprmatrix --region
hyprmatrix --hide        # Unmaps the surface and stops animation and wallpaper queries
hyprmatrix --show
hyprmatrix --toggle
hyprmatrix --toggle-workspace  # Toggle rain on the active workspace
hyprmatrix --drag-begin   # Region drag handshake used by the Super+left bind
hyprmatrix --drag-end
hyprmatrix --refresh     # Retry palette extraction at the next wallpaper check
hyprmatrix --quit
hyprmatrix --check-config
hyprmatrix --print-config
hyprmatrix --preview /tmp/hyprmatrix.png
hyprmatrix --preview-settings /tmp/hyprmatrix-menu.png
hyprmatrix --benchmark 3
```

Defaults: full screen, 20 FPS, 70% rain opacity, clear background, 55% column
density, 16px characters. The default output is the first advertised monitor.
Set `output = "eDP-1"` (or another connected output name) in the config to select a
monitor; restart after editing the file externally. It renders on one monitor per
instance. Output removal exits cleanly; launch again to select another output.

Wallpaper mode queries `awww` every five seconds while visible, selects the path
for the chosen output, and invokes `ffmpeg` only when the path or modification
time changes. A 48 × 48 thumbnail supplies a dominant saturated hue and overall
brightness. Dark wallpapers get luminous rain; light wallpapers get darker ink.
Colors transition smoothly. Neutral images use a teal/slate fallback. Missing
helpers or unavailable images retain the previous palette; Matrix green, cyan
and amber modes are also available. Palette contrast is global, not per glyph or
per wallpaper region. The refresh action retries even an unchanged image.

## Resource design

No web view, GTK/Qt runtime, GPU context, blur or bloom. Rasterized font glyphs are
cached and drawn directly into two reusable premultiplied ARGB Wayland SHM buffers.
There is no intermediate fullscreen image copy. Buffer pools are replaced on
resize. The logical desktop resolution is used at all display scales to bound
memory and rendering cost; compositor upscaling can soften text on HiDPI outputs.
Animation follows compositor frame callbacks and a configurable 5–60 FPS limit.
When the compositor withholds callbacks, animation rendering stops. Explicit Hide
also stops wallpaper queries. Wallpaper helpers have bounded output and a
three-second timeout. Per-surface allocation is limited to 16 megapixels.

Two 1920 × 1080 buffers use about 15.8 MiB; fonts, program code and the compositor
add memory. Resource usage depends on resolution, density, font size and FPS.
`--benchmark` measures the real rain renderer at 1920 × 1080 without sleeping;
its CPU estimate excludes the compositor and wallpaper helpers. Use 10 or 15 FPS
and lower density to reduce work further. Animation is intentionally character
stepped rather than a costly full pixel glow simulation.

## Build and integration

Dependencies: Rust/Cargo, Wayland with wlr-layer-shell, a DejaVu font. The existing
wallpaper tools `awww` and `ffmpeg` enable automatic colors. An alternate TTF may
be selected using `font = "/absolute/path/font.ttf"` in the config.

```sh
cargo test --locked --manifest-path apps/hyprmatrix-rs/Cargo.toml
cargo build --release --locked --manifest-path apps/hyprmatrix-rs/Cargo.toml
apps/hyprmatrix-rs/install.sh
```

The standalone installer installs only the binary, launcher and an absent config.
The main Hyprshell installer also builds the binary. Ordinary updates retain the
live app config, and explicit Sync to GitHub captures it without copying compiled
binaries. Nothing changes Hyprmonitor or existing desktop shortcuts. Autostart is
not enabled automatically; the application launcher starts it on demand.

For optional startup, add `hl.exec_cmd('uwsm app -- "$HOME/.local/bin/hyprmatrix"')`
to the existing `hyprland.start` handler in your startup Lua section.
