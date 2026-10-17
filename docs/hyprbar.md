# Classic Hyprbar — Phase 6

Hyprbar is the classic window taskbar. Enable it in Settings → Hyprpane & panels
→ Hyprbar after choosing an available edge. It defaults off, preserving the
existing arrangement. Placement validation still permits at most two visible
components on an output/workspace, on different edges; it never moves or disables
another component to make room.

The taskbar fills its edge and includes an application menu, ordered app pins,
and icon-only running-window buttons, with no tooltips. It shares the existing
ApplicationService, desktop-ID
matching, launch semantics and settings transactions with Hyprdock and the
launcher. Shared/separate pin lists remain available in Apps & windows.

- Click an idle pin to launch, a single-window button to focus, or a grouped
  button to choose a window. Focus preserves the pointer position.
- Right-click or press Menu / Shift+F10 for new instance, pin/unpin, focus, close,
  and a destination-workspace selector with an explicit Move button (1–99).
  Middle-click opens another instance of an installed app.
- Grouping is optional. Ungrouped buttons retain individual window addresses.
  Window titles remain in the window picker and context menu.
- App buttons use compact square icon targets on every edge, matching Hyprdock.
  Active and urgent windows retain visible emphasis. The current 32 px rail and
  24 px app icons fit inside the pill; old title-width values never widen Left/Right.
- Filters select current/all workspaces and current/all monitors independently.
  Filtering precedes grouping, so pickers and active emphasis describe only the
  included windows. Pins remain available when their windows are filtered out.
- Overflow scrolls with wheel/buttons; arrows, Home/End and Tab provide keyboard
  access. Enter/Space activates and Escape dismisses. Pins retain drag reorder
  and Ctrl+arrow ordering through the existing pin transaction.

Preferences live in `panels.hyprbar`. `grouped`, `windowWorkspaceScope` and
`windowMonitorScope` (`current` or `all`) control the app list. Legacy `showTitles`,
`buttonWidth` and `verticalWidth` remain readable for backups, but no longer change
the icon-only presentation. Existing placement, visibility,
dimensions and hide-mode fields remain supported. Missing fields inherit defaults
without rewriting saved preferences. Side-panel reserved width follows the icon
rail thickness; horizontal panels
own adjacent corners.

Alt+Z toggles Hyprbar and Alt+D toggles Hyprdock on the focused monitor's
current numbered workspace, matching Hyprpane's toggle (personally remapped
to Alt+X). Toggles persist an individual workspace override, retain global
enablement and other workspace choices, and respect panel layout conflicts.
When Settings is open they update its draft through the normal autosave flow.

Implementation uses the existing Dock/DockWindow/DockPopup surfaces with an
explicit component selector; their default remains Hyprdock. `TaskbarModel.js`
owns task filtering and grouping, and `SettingsTaskbarEditor.qml` selects Hyprbar in the common
`SettingsDockEditor.qml` controls. No additional discovery service, notification owner or periodic client
polling is created. Geometry sampling remains limited to eligible dodge panels.

## Right-side Hyprpane items

The trailing section (right on Top/Bottom, bottom on Left/Right) reuses Hyprpane's
controls and inward menus with the same desktop services, notification inbox,
tray and clock. By default, `rightItems: null` follows the current enabled
right-side Hyprpane items in their saved order. Hyprbar displays status icons
without labels or notification counts; the horizontal clock keeps its text.
Media shows its spectrum without a title. Hyprpane and Hyprdock retain their
existing label presentation.
The current selection is System tray, Notifications, Audio, Network, Bluetooth,
Battery and Power; conditional items retain their existing availability rules.

Settings → Hyprpane & panels → Hyprbar lists every Hyprpane item with an
independent switch. The first edit saves a separate ordered `rightItems` list;
`[]` gives an empty trailing section. “Use current Hyprpane right-side items”
returns to inheritance. Adding an item here does not move or remove it in
Hyprpane. Long status sections scroll independently, and app overflow stays
within its remaining space. Neither section shows item tooltips.

Hyprbar has separate Left item spacing and Right item spacing sliders (0–30 px).
On side edges these apply to the top app section and bottom status section.
The left slider saves `panels.hyprbar.spacing`; the right saves
`panels.hyprbar.spacingRight`. A missing or null right value preserves the existing
Hyprpane spacing until edited. Item-specific spacing offsets remain additive.
An explicit right spacing also removes the horizontal items' built-in pill
padding and square network/Bluetooth widths, so zero produces a compact row.
Custom padding and notification badge space remain available; Hyprpane keeps
its existing pill dimensions.

Hyprbar and Hyprdock also have Left inside padding and Right inside padding
sliders (0–100 px) for the space between item targets and the pill ends, separate
from item spacing and screen margins. On vertical panels these are Top and
Bottom inside padding. They save `paddingStart` and `paddingEnd` on each panel;
missing values preserve the existing 6 px app inset and 4 px trailing status inset.

One continuous `PanelPill.qml` backdrop spans the app and status sections. It
uses the current center Hyprpane pill's glass, rim and adaptive colors. Status
items retain their glyph colors and behavior but have no individual or group
backgrounds. Hyprpane's own pills remain unchanged. The common backdrop follows
all four edges, including rounded top/bottom ends on narrow side rails.

Minimize/restore remains unavailable: Phase 3 did not establish a recoverable
compositor implementation. Phase 7's [menu coexistence slice](panel-coexistence.md)
keeps the neighbouring panel reachable while menus are open and constrains cards
to the remaining space. The optional [Show Desktop control](show-desktop.md)
now includes persistent recovery. Real workspace/fullscreen, reveal input and
virtual hotplug checks pass. Connected external-display checks also pass;
remaining cable-cycle/tray checks were deferred by the user at plan closure. Searchable schematic layout previews and explicit
placement presets are implemented in the [Phase 8 settings slice](panel-layout-settings.md).

## Validation — 2026-10-16

The Qt 6 suite passed 256 checks, including four-edge taskbar pointer/keyboard
activation, grouped/ungrouped models, icon-only layout, overflow and Move actions.
The native Quickshell taskbar test passed with the real ApplicationService and
isolated preferences: output/workspace filtering, grouping, close/title/focus
updates and orientation changes. The native fixture also composes the inherited
right-side items beside the app icons.
Focused Qt checks cover inherited/custom/empty status selections, four-edge
menu clicks, bounded media sizing, and absent app tooltips. The existing native
dock launch/pin/reorder
check and Settings search checks passed. Backend coverage checks inherited
preferences, invalid taskbar fields, allowed pairs and conflict rejection.

Layer-shell placement, compositor actions, physical input and fullscreen/output
transitions need an accessible desktop session. `hyprctl -j monitors` returned
`Couldn't set socket timeout (2)` here. Offscreen Quickshell has no PanelWindow
backend, so the native taskbar test uses a regular window and does not claim
layer-shell placement passed. Live configuration files are copies; matching
source changes are deployed with a dated backup. The user's requested styling
update changes only dock/taskbar thickness, icon size and spacing in saved
preferences; visibility, selected edges and other preferences remain intact.
`tests/test_panel_style.py` renders Hyprpane, Hyprdock, and horizontal/side
Hyprbar in a native composition, checks 32 px side rails, square targets and absent status backdrops,
and exports `/tmp/hypr-panels-style.png` for visual review.

Hyprbar and Hyprdock now expose the same controls, including utilities, opacity,
visibility policies, indicators, grouping, window filters, and trailing system
items. Their presentation differs by length: Hyprbar fills the edge; Hyprdock
fits its contents and centers by default. Hyprdock defaults to no system items,
while Hyprbar retains inheritance. Running apps use a small lower-right dot
instead of an underline: bright green when active, bright yellow otherwise.
Icon size no longer increases pill thickness.
