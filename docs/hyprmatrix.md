# Hyprmatrix

A separate Rust digital-rain desktop effect for Hyprland. It uses a native
Wayland layer surface above the wallpaper. Settings → Window layer selects
Behind (the default) or In front of application windows; the choice is saved as
`in_front` and applies immediately. Rain keeps passing clicks through in either mode.
It has no title bar, borders, dock entry or taskbar window.

## Use

Launch **Hyprmatrix** from the app launcher to start it and open settings, or run
`~/.local/bin/hyprmatrix` for rain alone. **Super+Alt+M** opens settings,
starting Hyprmatrix if needed. There is no invisible hover target; the closed
effect passes all pointer input through to the desktop. Settings stay open until
the pointer enters and leaves the panel, then close after 180ms. Dragging keeps
settings open until release. Right-clicking the panel or choosing Close settings
also closes it; Escape dismisses it too. Every opening centers the panel on the
effect's output and moves the cursor into its header after the surface maps,
matching the launcher popup. `hyprmatrix --settings` opens the same menu from a shell.
Super+right-click along the screen's right edge also opens settings.
The invisible target extends 48 logical pixels inside and 16 pixels outside the
edge for its full height. Misses are quiet and retain window resizing; application
windows under the pointer keep priority when Window layer is Behind. Open settings temporarily
raise the rain surface above application windows; closing restores the selected Window layer.

The rounded settings panel uses translucent charcoal glass, a subtle top gradient,
a tinted rim and compositor blur, with a proportional UI font and blue controls.
All appearance, window-layer and visibility controls share one page. Its separate
`hyprmatrix-settings` overlay confines blur to the popup, keeping the rain clear.
Dragging repositions the panel until the next opening, which centers it again.

Use the left and right arrows in each value control to decrease or increase it.
Hyprmatrix always covers the full monitor; the smaller region mode has been removed.
Existing region configurations open fullscreen while retaining appearance and workspace preferences.
Rain opacity and black background opacity are independent; background zero leaves
the wallpaper fully visible. Changes save immediately to
`${XDG_CONFIG_HOME:-~/.config}/hyprmatrix/config.toml`. A failed save keeps the old
settings and reports the error inside the menu. Dragging the settings panel moves
only the panel. Super+left-drag moves application windows normally.

Rain visibility is remembered per
workspace: Alt+M toggles the active workspace, `hyprmatrix --toggle-workspace`
does the same from a shell, and the app keeps running while a workspace hides the
effect. Toggles are stored under `[workspace_overrides]` in the config;
workspaces without an entry keep rain off, and a fresh start enables the launch
workspace once so the first launch already shows rain.

Commands:

```sh
hyprmatrix --settings
hyprmatrix --settings-at-cursor # Right-edge hit test used by Super+right-click
hyprmatrix --fullscreen
hyprmatrix --hide        # Unmaps the surface and stops animation and wallpaper queries
hyprmatrix --show
hyprmatrix --toggle
hyprmatrix --toggle-workspace  # Toggle rain on the active workspace
hyprmatrix --refresh     # Retry palette extraction at the next wallpaper check
hyprmatrix --quit
hyprmatrix --check-config
hyprmatrix --print-config
hyprmatrix --preview /tmp/hyprmatrix.png
hyprmatrix --preview-settings /tmp/hyprmatrix-menu.png
hyprmatrix --benchmark 3
hyprmatrix --benchmark-settings 3
hyprmatrix --font-license
```

Defaults: full screen, 20 FPS, 70% rain opacity, clear background, 55% column
density, 16px characters. Rain columns are evenly spaced; Density adjusts their
uniform horizontal gap rather than randomly hiding columns. At 100%, each character
cell still has 4px of horizontal breathing room. Each lane continues across the
screen edge without a blank interval between passes. The default output is the first advertised monitor.
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

## Effects

Appearance → Effect switches immediately between **Matrix**, **Shooting stars**,
**Meteors**, and **Asteroids** and saves the choice. Existing configurations keep
Matrix. Matrix retains evenly spaced character columns.

Shooting stars and meteors use balanced left, center and right birth regions.
Each group offers all three regions an event, with independent random positions,
headings and birth times; there is no visible left/center/right rotation. Side
headings mirror each other. About 65% of central events start near the top and
fall exactly straight down; other events ignite across the upper and middle sky.
Streaks brighten and burn out inside the view, with irregular gaps,
overlaps and occasional two- or three-event clusters.

Shooting stars mixes fine streaks with brighter meteors (about 20% of non-comet
events) and occasional comet-like streaks (about 8%). Meteors mode keeps its
brighter streaks and includes these longer, slower comet-like passes too. The
latter have a faint spreading tail around a narrow luminous core. Ordinary
streaks last at most about 7 seconds and comet-like passes at most about 20 seconds
at the default Speed and Particle size. These are stylized sky effects, with procedural trails.

Fine tapered trails grow behind small neutral-white heads, then shorten as the
event fades. Color tints the trail and halo. Density controls both the starfield
and event frequency, with moving activity rising more strongly toward 100%.
Moving activity is comparable to Matrix's simultaneous stream count
at matching Density/Particle size, with about 10% fewer simultaneous streaks than
the previous tuning. The gentle density curve keeps lower settings active too.
Shooting stars and Meteors have about 15% more stationary stars (about
120 at 1080p/100%), with a mix of small points and larger stars across the upper
half of the screen. Comet-like passes share the adjusted event frequency.
Screen width and streak lifetimes scale
event frequency so smaller screens keep a similarly busy sky.
Very low density retains quiet gaps.
Speed scales motion and timing. Ordinary streaks match Matrix's typical pixel
speed at the same Speed and size settings; comet-like passes remain slower.
Particle size scales heads and trails, with motion following Matrix's character
row height. Matrix's density, motion and drawing remain unchanged.

Asteroids retain predominantly upper-left to lower-right paths, occasional other
downward headings, and steady size/speed during each tumbling pass. They cross the
view and exit without wrapping. About 90% of sizes stay within 6% of Particle
size, with occasional 20% smaller/larger rocks; about 90% of speeds stay within
4% of Speed, with occasional 25% slower/faster passes. These variations are
independent.

All three space modes include a subtle stationary starfield; Asteroids retains
its existing full-screen starfield and particle counts. Each star stays in
place with a fixed size and brightness for most of an 18–40 second lifetime,
then fades away and returns at a new position, size and brightness. These stars
use a cool neutral light, including in Asteroids mode, and renew independently
of the moving-particle Speed setting. Density and opacity apply to them too.
Shooting stars have fine tapered streaks and small luminous heads; meteors have
longer, thicker trails and brighter heads; asteroids are shaded, tumbling rocks
with craters. They are drawn procedurally without image assets or a GPU context.

Color, rain opacity, background, density, speed and frame limit apply to every
effect. Character size becomes Particle size for space effects. Lower Density
widens Matrix column spacing or reduces the number of sky events; zero hides
all particles. The Window layer control shares the settings page with appearance
controls. Reset appearance restores Matrix and the usual defaults.
The saved `effect` values are `matrix`, `shooting_stars`, `meteors`, and `asteroids`.

## Resource design

No web view, GTK/Qt runtime, GPU context or rain blur/bloom. Settings use the
compositor's blur through a separate, panel-sized overlay and repaint only when
the controls change. The default rain and UI
fonts use a built-in ASCII bitmap atlas, retaining the original DejaVu coverage
without parsing or keeping whole fonts in memory. The atlas license is available
with `--font-license`; its reproducible generator is
`apps/hyprmatrix-rs/examples/generate-font-atlas.rs`. An explicitly selected custom
TTF still uses fontdue. Only the current rain size is cached.

A persistent character grid tracks changed symbols and brightness. Only damaged
tiles are cleared, repainted and sent to Wayland; unchanged frames need no upload.
Settings are cached while open and released on closing. One premultiplied ARGB
SHM buffer is reused only after compositor release, without an extra full-screen
image copy. If a compositor retains that buffer for 200 ms while a replacement
is needed, a second is allocated as a compatibility fallback; its frames are
fully seeded when switching buffers. Buffer pools are replaced on resize. The logical desktop resolution is used at all display scales to bound
memory and rendering cost; compositor upscaling can soften text on HiDPI outputs.
Animation follows compositor frame callbacks and a configurable 5–60 FPS limit.
When the compositor withholds callbacks, animation rendering stops. Explicit Hide
also stops wallpaper queries. Wallpaper helpers have bounded output and a
three-second timeout. Per-surface allocation is limited to 16 megapixels.

One 1920 × 1080 buffer uses about 7.9 MiB; program code, caches, Wayland and the
compositor add memory. Sharp full-screen rain at that size cannot fit within a
5 MB total process budget with this SHM design. Resource usage depends on
resolution, density, font size and FPS. `--benchmark` measures the rain renderer
at 1920 × 1080 without sleeping; `--benchmark-settings` includes the settings
panel. These report
process RSS and estimate rendering CPU, excluding live Wayland/compositor work and wallpaper helpers. The benchmark uses one pixel
buffer, like the desktop path; it is not a live desktop resource measurement.

Local comparison on 2026-10-21 with Matrix color, 100% density, 14 px glyphs and
15 FPS: renderer-only steady RSS decreased from 40.1 MiB to 12.2 MiB, with frame
cost 0.406 ms → 0.266 ms (estimated 0.6% → 0.4% of one core at 15 FPS). With
settings open, the new renderer measured 12.9 MiB and 0.306 ms/frame. Rain and
settings preview PNGs remained byte-identical to the preceding build. These are
isolated measurements. A final run after making the UI glyphs load only while
settings are open measured 12.0 MiB / 0.251 ms at 1080p, 12.6 MiB / 0.294 ms
with settings, and 5.2 MiB / 0.052 ms at the saved 640 × 520 widget size. The
corresponding estimates at 15 FPS are 0.4%, 0.4% and 0.1% of one core.
Live desktop CPU/RSS and compositor buffer-release
behavior remain unverified because session sockets are inaccessible in the
agent sandbox. cmatrix's process accounting excludes its terminal renderer, so
a process-only comparison does not measure the same complete rendering path.

Use 10 or 15 FPS and lower density to reduce work further. Animation is
intentionally character stepped rather than a costly full pixel glow simulation.

## Build and integration

Dependencies: Rust/Cargo and Wayland with wlr-layer-shell. The built-in bitmap
atlas covers the default fonts; DejaVu fonts are needed only to regenerate it. The existing
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
