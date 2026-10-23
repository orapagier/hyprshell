# Hyprpane layout preview and presets

Settings → Hyprpane → Panel layout preview & presets shows draft placement for
a monitor and workspace. Selection does not save. Apply layout preset changes
only `bar.position` to Top, Bottom, Left, or Right, preserving appearance, item
ordering, monitor choices, enablement and workspace visibility.

The schematic shows whether Hyprpane is enabled and visible on the selected
monitor/workspace. It does not simulate pixel dimensions or compositor rendering.
`PanelLayout.js` builds the draft and preview row; `SettingsPanelLayout.qml`
provides the controls. `tst_PanelLayout.qml` checks presets, visibility and geometry.
See [configuration](panel-configuration.md) and [persistence](panel-persistence.md).
