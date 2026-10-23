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
