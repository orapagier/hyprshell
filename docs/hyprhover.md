# Hyprhover

When Hyprpane is hidden on an output's active workspace, Hyprhover automatically
provides three top-edge drawers: left corner, screen center, and right corner.
Use the configured Hyprpane toggle (Alt+X on this desktop) or workspace visibility
settings to switch between them. Bottom dashboard and activity corners remain.

Drawers attach directly to the screen with concave curved feet, matching the
dashboard. Corner drawers join both adjacent edges; the centered drawer joins
the top edge with two feet. There is no popdown stem. Glass and spring motion
follow the dashboard's appearance.

Each saved, available Hyprpane item becomes a labeled tab, preserving group and
order. Hover, click, or keyboard focus selects a tab and loads its controls inside
the drawer. Apps, workspaces, media, settings, calendar, tray, notifications,
audio, Wi-Fi, Bluetooth, battery and power all have inline pages. Switching pages
releases the previous page's scans/captures. Tabs stay in one horizontally scrolling row; wheel, trackpad, drag, and keyboard
focus reach overflow tabs. Tall content scrolls vertically.

Entry is immediate, with the dashboard's 900 ms handoff grace and 320 ms leave
dismissal. Escape, outside click, workspace changes and restoring Hyprpane close
the drawer. No new preference migration is needed.

Implementation: `Hyprhover.qml`, `HyprhoverSurface.qml`, `HyprhoverContent.qml`.
Native lifecycle, tab and attachment checks: `tests/test_hyprhover.py`.
