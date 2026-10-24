# Hyprpane layout preview and presets

Settings → Hyprpane → Layout & visibility → Panel layout preview & presets shows draft placement for
a monitor and workspace. Selection does not save. Apply layout preset changes
only `bar.position` to Top, Bottom, Left, or Right, preserving appearance, item
ordering, monitor choices, enablement and workspace visibility.

The schematic shows whether Hyprpane is enabled and visible on the selected
monitor/workspace. It does not simulate pixel dimensions or compositor rendering.
`PanelLayout.js` builds the draft and preview row; `SettingsPanelLayout.qml`
provides the controls. `tst_PanelLayout.qml` checks presets, visibility and geometry.
See [configuration](panel-configuration.md) and [persistence](panel-persistence.md).

Hyprpane settings use category buttons that wrap on narrower windows:

- **Layout & visibility**: layout presets, screen edge, thickness, side-panel
  length, full background and transparency, attachment, autohide, and workspace visibility.
- **Items & spacing**: alignment, uniform sizing, general icon size, item gaps,
  outer margins, and inner padding, plus direct shortcuts to every individual
  item editor. The Hyprpane settings button returns to the selected category.
  The interactive preview and sidebar’s Hyprpane items list also open item editors.
- **Appearance**: colors, individual and shared backgrounds and transparency,
  and Hyprknots with their line and knot dimensions.
- **Menus & clock**: hover defaults and workspace overrides, popdown glass,
  and clock formatting.
- **All settings**: every group in one view.

Searching exposes all categories and expands matching cards. Clearing search
returns to the selected category. Category changes do not edit preferences;
all original controls, inheritance, and save behavior remain available.
