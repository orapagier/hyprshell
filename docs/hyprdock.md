# Hyprdock

Hyprdock is an optional Hyprpane presentation, selected with **Settings →
Hyprpane → Layout & spacing → Use Hyprdock** (`bar.dockEnabled`). The saved
personal preset enables it; schema defaults keep older installations on their
existing panel. Disabling it restores the saved ordinary Hyprpane layout.

## Interaction

- At rest, an attached clock shows `HH:mm`. It reserves no workspace area.
- Entering the dock's screen-edge base reveals the item strip. The first four
  pixels are a reveal-only region, so reaching the edge does not open a menu.
- The item strip stays fixed on the screen as content changes size.
- Hover an item to expand content inside the same attached surface; click to
  pin it. Moving between the strip and content retains the expansion.
- Leaving the entire dock closes an unpinned expansion after a short delay. The strip then
  returns to the compact clock when the pointer is outside.
- **Alt+Shift+T** reveals and focuses the strip. Arrows/Tab navigate controls,
  Enter activates, and Escape returns to the strip then collapses the dock.
- Existing launcher, status-menu, **Super+D**, **Super+K**, **Alt+S**, and
  **Super+P** shortcuts open the corresponding dock content.
- **Alt+T** retains its workspace visibility behavior. Direct menu shortcuts
  can temporarily open the dock on a hidden workspace.

The additional strip controls open Dashboard, Activity, and Keyboard shortcuts.
The existing enabled item order and workspace/tray behavior are reused. The
strip scrolls when it cannot fit. The dock expands horizontally on top/bottom
edges and vertically on side edges; larger content is bounded by the screen.
Settings retains its existing scrollable editor, with horizontal scrolling on
screens narrower than the editor's minimum useful width.

The battery is a vertical filled outline with a charging mark; Wi-Fi uses
ascending strength bars and a disconnected slash. These drawings apply only to
Hyprdock. Ordinary Hyprpane retains its original icons. Clock/calendar text
customizations remain saved for ordinary panel mode.

## Shared content and lifecycle

`Hyprdock.qml` owns the layer surface, input mask, spring animation, palette,
menu state, and content routing. Its single attached background samples the
wallpaper under the dock. Reduced motion disables the spring behaviors. Input
is limited to the dock's bounds; opening content does not resize applications.

Calendar, audio, Wi-Fi, Bluetooth, battery, power, notifications, media and
workspace previews reuse their existing content components. Launcher, shortcut
guide, Dashboard, Activity, Settings and projector controls are hosted there
as well. Notification popups appear inside the focused output's dock; the
ordinary corner popup stack is unloaded in dock mode. Security locking and
actual projected/captured views retain their dedicated surfaces.

Settings retains its existing controller and editor, save queue, failed drafts,
manual page edits, and in-flight jobs. Only its visual root is reparented into
the dock; the native editor window is not mapped. Embedded dialogs belong to
that visual root, and wallpaper sampling follows the dock's output. Dashboard
and Activity remain loaded after first use so navigating away cannot terminate
an in-flight write. Their visible-only sampling remains gated by the section.

Only one output's dock content is active at a time. Workspace changes dismiss
content. The legacy hot corners and Hyprhover are inactive in dock mode.

## Verification

`tests/test_hyprdock.py` runs production dock content in an isolated offscreen
Qt window. It checks routing, embedded Settings, four-edge bounds, reveal-only
base behavior, hover retention/dismissal, launcher keyboard focus, Escape state,
and notification placement/dismissal. Only layer-shell window properties are
replaced for the offscreen backend. Adjacent Settings, panel, and shortcut-guide
tests cover preservation of existing behavior.

Physical pointer targeting, compositor keyboard focus, and spring feel require
an accessible running Hyprland session; offscreen checks cannot certify those.
