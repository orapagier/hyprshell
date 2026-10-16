# Panel layout settings — Phase 8 preview and preset slice

Settings → Hyprpane & panels → Panel layout preview & presets shows a schematic
of the current draft. Edge changes in the existing editors update it immediately.
Choose a monitor name and workspace to check saved visibility scopes and individual
workspace overrides. An empty monitor name represents monitors absent from saved
monitor lists. Disabled and hidden-here panels are distinguished in the legend;
auto-hide and overlap-hiding panels use faded edges. Horizontal panels own corners.
The schematic describes placement, not pixel dimensions or current hover/fullscreen
visibility. Existing detailed appearance and item previews remain available.

Six presets offer Hyprpane Top + Hyprdock Bottom, Hyprpane Top + Hyprbar Bottom,
Hyprdock Left + Hyprbar Bottom, or any single component. Selecting one only previews
it. **Apply layout preset** explicitly enables the selected components, disables
the others, and assigns the selected edges in one draft update. The normal backend
transaction validates and saves the entire change, without intermediate conflicts
from enabling a third panel or assigning the same edge temporarily.

Presets retain styling, dimensions, margins, hide modes, status selections, shared
and separate pins, monitor lists, visibility defaults and workspace overrides.
Disabled components retain their last edge. A selected component can therefore
remain hidden on a particular workspace or monitor; the preview makes that visible
and the existing editors control those choices. No preset is applied during setup,
search, preview selection, or migration.

`PanelLayout.js` owns placement-only transformations. `SettingsPanelLayout.qml`
uses the same `SettingsModel.js` visibility and conflict checks as the runtime.
`SettingsBarEditor.qml` and `SettingsWindow.qml` pass one candidate to the existing
autosave transaction. No settings keys, schema version, services or timers were
added; setup and sync already include these QML/JS sources.

Validation covers all six presets through the native Settings window and real
backend saves in an isolated config root, including preservation of custom pins,
monitor lists, workspace overrides, thickness and status selection. Qt tests cover
read-only preview, Apply, all four edges, corner handling and visibility scopes;
settings search tests cover the new card and controls. Existing panel validation,
transaction rollback and conflict tests remain applicable.

The combined Qt 6 suite passed 312 checks (11 in the new fixture). Focused Python
validation passed 55 tests across native layout saves, panel configuration,
settings transactions and static/native search. All three changed QML components
passed Qt's parser. The Qt suite retains existing dock fixture warnings; the
native Settings tests reject binding loops, assignment errors and JS errors.

Only the matching QML/JS source and Qt fixture are deployed to the installed
configuration after validation, with previous files backed up. Saved desktop
preferences are untouched. Physical layer-shell, fullscreen, scaling and monitor
hotplug checks still require an accessible compositor. Show Desktop remains
pending as described in [Panel coexistence](panel-coexistence.md). The automated
setup, update, sync and backup/restore transaction matrix is now recorded in
[panel persistence](panel-persistence.md). Physical acceptance remains pending.
