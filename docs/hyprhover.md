# Hyprhover

When Hyprpane is hidden on an output's active workspace, Hyprhover automatically
provides three top-edge hover drawers: left corner, screen center, and right
corner. Alt+T and the existing workspace visibility settings switch between them.
The existing bottom dashboard and activity corners remain available.

Each drawer uses the corresponding saved Hyprpane item group, order, enabled
state, and actions. It shares the dashboard's immediate hover entry, 900 ms
handoff grace, 320 ms leave dismissal, Escape/outside-click dismissal, and glass
popover renderer. Controls open their usual menus; a child menu retains its
parent drawer. Workspace changes and restoring Hyprpane close the drawers.
Wide groups scroll horizontally. No new settings or preference migration is needed.

Implementation: `Hyprhover.qml`, per-output wiring in `shell.qml`, and the optional
`Bar.onlySide` filter. Native offscreen coverage: `tests/test_hyprhover.py`.
