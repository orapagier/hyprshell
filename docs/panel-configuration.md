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
included in the full panel background, when enabled. Controls autosave and apply
to both the Settings item preview and the live panel without changing item order,
group membership or menu anchoring.
