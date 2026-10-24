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

Default end margins are 10 px. Full Pill adds 5 px between its ends and the
first/last item. Without Full Pill, items start at the 10 px screen margin.
Individual items have 5 px base left/right padding, including text. Inner-padding
controls add space to these defaults; individual padding offsets remain available
when uniform mode is disabled.

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

Centered layouts place ordinary icons in equal square slots, including a calendar
icon for date/time and a compact media spectrum. Workspace numbers use their
saved compact font and use circular pills at 40% of panel thickness, smaller
than other item pills. One- and two-digit workspaces keep identical spacing.
Normal-mode workspace names and custom appearance remain saved. Notification counts and status text remain
available in their menus. The normal text layout returns when centering is
disabled; saved item text, icons and appearance are retained. With background
pills enabled, icons and numbers stay centered inside their pills. Item pills
occupy 60% of Full Pill's thickness, leaving 20% on each side. Default icon and
text ink height is 80% of its own pill (48% of the full thickness). Workspace
pills occupy 40%, leaving 30% on each side; default numbers fit within 80% of
that pill in both dimensions. These proportions follow panel thickness on all
four edges, with Full Pill enabled or disabled. A size of 0 selects automatic
sizing; explicit icon/font sizes remain available.

The active item-gap control (with or without Hyprknots) applies to centered
items in every group, workspace buttons, tray icons, shared-pill members and
section boundaries. Empty groups add no gap. Shared-pill spacing remains saved
for individual mode; before/after adjustments apply when uniform mode is off.
Only the applicable gap control is enabled for the current mode.

**Uniform icon size & spacing** (`bar.uniformItems`, default true) uses the
General icon size for launcher/settings marks, status icons, calendar, media
spectrum and tray artwork as the default. Individual icon and text sizes take
priority, including workspace number fonts. Text labels share the same font
scale using a percentage reference, so dates and audio percentages match when
their text sizes match.
Ordinary horizontal layouts size pills around visible glyph bounds with 5 px
padding on either side; Bluetooth and Wi-Fi no longer reserve an unrelated
square width or font-bearing space. Centered layouts use equal square slots
for ordinary items and smaller workspace slots. Each keeps the same footprint
whether backgrounds are shown or hidden. Text labels remain available
in the ordinary layout, and workspace numbers retain independent font overrides
and their smaller 40% pills.

The active item gap applies to every group, shared pill, workspace button and
tray icon in either layout. Individual sizes apply immediately; padding/gap overrides remain saved and
apply when uniform mode is off. Side panels retain their circular
controls and use the same icon size and item gap. Group positions still follow
the selected centered or ordinary layout.

### Screen attachment and autohide

Hyprpane → Layout & spacing → **Attach to screen edge** adds a continuous
surface with curved feet directly against the selected screen edge. It works
with centered or spread items and compact side panels, without a screen frame.
The selected edge margin is temporarily ignored; saved margins remain intact.
**Autohide attached Hyprpane** reveals it from a 2 px edge strip with an elastic
animation, delays hiding on pointer exit, and retains it while a menu is open.
Autohide reserves no space for the panel. Workspace/output visibility still
applies. Both options default off; autohide takes effect only while attached.
Preferences are `bar.edgeAttached` and `bar.autoHide`.
