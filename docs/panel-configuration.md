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

Centered layouts display icons only, including a calendar icon for date/time,
filled/hollow workspace indicators, and a compact media spectrum. Notification
counts and status text remain available in their menus. The normal text layout
returns when centering is disabled; saved item text, icons and appearance are
retained. Centered icons share consistent slot sizes, so former text padding does
not produce visibly different icon spacing.

The active item-gap control (with or without Hyprknots) applies to centered
items in every group, workspace buttons, tray icons, shared-pill members and
section boundaries. Empty groups add no gap. Shared-pill spacing remains saved
for the ordinary layout; individual before/after adjustments still apply.
Only the applicable gap control is enabled for the current mode.
