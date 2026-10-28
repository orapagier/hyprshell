# Hyprhover

When Hyprpane is hidden on an output's active workspace, Hyprhover automatically
provides three top-edge drawers: left corner, screen center, and right corner.
Use the configured Hyprpane toggle (Alt+X on this desktop) or workspace visibility
settings to switch between them. Bottom dashboard and activity corners remain.

Drawers attach directly to the screen with concave curved feet, matching the
dashboard. Corner drawers join both adjacent edges; the centered drawer joins
the top edge with two feet. There is no popdown stem. Glass and spring motion
follow the dashboard's appearance.

Each saved, available Hyprpane item becomes a circular icon tab, preserving group and
order. Hover, click, or keyboard focus selects a tab and loads its controls inside
the drawer. Apps, workspaces, media, settings, calendar, tray, notifications,
audio, Wi-Fi, Bluetooth, battery and power all have inline pages. Switching pages
releases the previous page's scans/captures. Item tabs and numbered workspace selectors each stay in one fixed row of circles.
Circles shrink to fit the available width; neither row scrolls or wraps. Hover or
keyboard focus previews a workspace; clicking activates it. Tall page content
scrolls vertically.

Entry is immediate, with the dashboard's 900 ms handoff grace and 320 ms leave
dismissal. Escape, outside click, workspace changes and restoring Hyprpane close
the drawer. No new preference migration is needed.

Implementation: `Hyprhover.qml`, `HyprhoverSurface.qml`, `HyprhoverContent.qml`.
Native lifecycle, tab and attachment checks: `tests/test_hyprhover.py`.
