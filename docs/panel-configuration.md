# Hyprpane configuration

Hyprpane is the status/menu panel on any edge. Settings → Hyprpane retains its
appearance, item ordering, workspace visibility and layout preview controls.

Schema version remains 1. The canonical payload is `config/hyprshell/settings.json`;
`settings/defaults.json` supplies omitted fields. Save, setup, sync and recovery
use backend validation. Invalid writes retain the previous saved settings.

| Preference | Stored source |
| --- | --- |
| Enable / monitor selection | `panels.hyprpane.enabled`, `.monitors` |
| Edge | `bar.position` |
| Workspace visibility | `bar.visible`, `.workspaceScope`, `.workspaceList`, `.workspaceOverrides` |
| Dimensions | `bar.height`, `.marginTop`, `.marginSide`, `.paddingBottom` |
| Styling and item layout | Remaining `bar` fields and `items` |
| Hide mode | `panels.hyprpane.hideMode`: `always` |

`Bar.qml`, `SettingsBarEditor.qml`, IPC target `bar`, `toggleBar`, backend
`--toggle-bar WORKSPACE`, and shortcut helper `topbar` target Hyprpane. Alt+T
toggles the current workspace. The enabled flag is a master gate; workspace
overrides take priority over ordinary scope defaults. An empty monitor list means
all outputs; disconnected connector names are retained for hotplug.

`pins.matches` retains explicit application identity corrections used by the
launcher/window service. See [application support](application-support.md).

Settings → Hyprpane has separate item gaps with and without Hyprknots.
Disabling Hyprknots uses `bar.compactSpacing` (3 px by default), including
workspace buttons, and re-enabling restores `bar.spacing`. Shared-pill spacing
and individual item offsets remain independent.

**Outer margins** provides physical Top, Bottom, Left and Right overrides
(`bar.screenMarginTop/Bottom/Left/Right`, 0–200 px). Reset follows the existing
Edge margin / End margins controls. The inward-facing side reserves extra space
toward windows, in addition to Gap toward windows. Compact side panels center
within the remaining top/bottom margins.

**Inner padding** provides independent Top, Bottom, Left and Right controls
(`bar.contentPaddingTop/Bottom/Left/Right`, 0–100 px, default 0). Padding expands
the panel thickness and compact side-panel length and insets its items. It is
included in the full panel background, when enabled. Hyprknots follow the
padded content center, and wallpaper sampling covers the occupied strip rather
than the empty padding. Geometry sliders preview on the live panel while dragging,
coalesce pointer updates, and save through the existing validated transaction.
Closing Settings or a save error clears the temporary preview.

Zero inner padding means no **additional** inset. Existing Edge margin and End
margins still position the panel, and individual pills retain their own padding.
Hyprland's `general.gaps_out` controls window gaps separately; it does not inset
Hyprpane's contents. Equal left/right insets preserve the center group at the
screen center; left/right groups retain their saved edge alignment.

Controls autosave and apply
to both the Settings item preview and the live panel without changing item order,
group membership or menu anchoring.

**Layout & spacing → Center all items** (`bar.centerItems`, default false)
places the left, center and right groups together at the screen center, in that
order. Each group retains its saved membership, order, individual offsets and
shared pills. Nonempty groups use the normal section gap; empty groups add no
gap. The whole collection is centered, so the center group itself can move away
from the screen midpoint. Padding bounds constrain placement near screen edges.
The switch previews immediately and autosaves. Turning it off restores the
usual edge alignment. On side panels it centers the three groups vertically;
the existing Full edge / Compact length selection is retained.

With **Center all items** enabled, connected popdown cards follow their actual
triggering icon, including workspace and media previews. Cards stay within the
screen boundaries and update while icons move. Saved left/center/right group
membership continues to control layout; disabling centering restores ordinary
menu alignment. Hidden-panel shortcuts and the application launcher overlay
retain their existing placement.

Centered layouts display icons with small workspace numbers, including a calendar
icon for date/time and a compact media spectrum. Horizontal workspace pills keep
the ordinary layout’s compact text-sized width, height, padding and number font,
including two-digit numbers; centering does not enlarge them into icon circles.
Normal-mode workspace names and custom appearance remain saved. Notification
counts and status text remain available in their menus. The normal text layout
returns when centering is disabled; saved item text, icons and appearance are
retained. Uniform mode sizes controls around visible content with equal padding,
so narrow glyphs do not leave extra blank space.

The active item-gap control (with or without Hyprknots) applies to centered
items in every group, workspace buttons, tray icons, shared-pill members and
section boundaries. Empty groups add no gap. Shared-pill spacing remains saved
for individual mode; before/after adjustments apply when uniform mode is off.
Only the applicable gap control is enabled for the current mode.

**Uniform icon size & spacing** (`bar.uniformItems`, default true) uses the
General icon size for launcher/settings marks, status icons, calendar, media
spectrum and tray artwork. Workspace number font choices remain independent.
Both centered and ordinary horizontal layouts size pills around visible glyph
bounds with 4 px padding on either side; Bluetooth and Wi-Fi no longer reserve
an unrelated square width or font-bearing space. Text labels remain available
in the ordinary layout, and workspace pills keep compact text sizing.

The active item gap applies to every group, shared pill, workspace button and
tray icon in either layout. Individual size/padding/gap overrides remain saved;
turn uniform mode off to use them again. Side panels retain their circular
controls and use the same icon size and item gap. Group positions still follow
the selected centered or ordinary layout.
