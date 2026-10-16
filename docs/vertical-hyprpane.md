# Vertical Hyprpane — Phase 2

On Left and Right, text is a column of upright characters, one per line, as
requested on 2026-10-16. Text length uses height and does not increase pane width.
The default width is 40 logical pixels; explicit thickness, font/icon sizes and
inside padding still apply. Unicode surrogate pairs, common combining accents,
variation selectors and joined icons stay intact instead of splitting symbols.
Top and Bottom retain their horizontal labels and layout.

Settings → Hyprpane & panels → Layout & spacing → Side panel length offers
Full edge and Compact (`bar.verticalPresentation`, default `edge`). Compact
centers the shorter pane and keeps Top/Center/Bottom groups together. Full edge
keeps their saved alignment, constraining the middle group to prevent overlaps.
Both preserve item ordering, enabled flags, text/icon visibility, colors, shared
pills, custom radii, margins and spacing. Vertical default corners are 8 px.

Long content scrolls in the pane with a visible scrollbar. Wheel over status
items, drag, use the scrollbar, or Tab to a control to reveal it. Workspace-wheel
switching and tray scroll actions still work. Tray icons have at least 24 px hit
areas and use extra columns when width allows; keyboard Enter and Menu actions
retain access to activation and context menus. Settings preview hit testing and
drag/drop account for scrolling.

The clock keeps the saved format and custom text, stacking its characters;
word separators become blank rows. Hover shows the unstacked text. Media labels
show at most 12 characters including an ellipsis, with the complete title or
custom label in the tooltip. Notification counts stack below the bell, keeping
every digit. Side menus open inward beside their trigger, remain inside the
available screen area, and scroll long pages. Keyboard focus reveals controls
inside both the pane and menu viewport. Existing Settings card/button actions
are preserved through the menu viewport.

## Reviewed images

These are Qt 6 software-rendered fixtures, not captures of personal notifications
or a physical desktop. They show a long date, active media, tray, 999 notifications,
volume, Bluetooth, network, battery, workspaces and an inward calendar card.

[Left layout](assets/hyprpane-phase2-left.png) ·
[Right layout](assets/hyprpane-phase2-right.png)

## Validation — 2026-10-16

- Full Qt 6 QML suite: 193 passed, covering existing horizontal behavior, menu
  hover and Settings card actions, shared appearance, workspace visibility and
  preview drag/drop, plus the new vertical layout scenarios.
- Focused vertical suite: 16 passed at 150% scale; normal-scale checks also pass.
  Scenarios include Left/Right, Full edge/Compact, 480×400 logical displays,
  18 tray items, long dates/titles, 999 notifications, custom labels, hidden
  text/icons, large fonts, shared pills, Unicode icons, scrolling preview hit
  testing and keyboard activation. Top and Bottom labels are checked separately.
- Backend/settings/search/recovery/sync/configuration tests: 83 passed. New
  presentation settings inherit correctly, round-trip, and reject invalid
  values without writing. Existing saved preference values remain intact.
- Setup: 18 checks, one skipped. Native caption search passed. Hyprland's
  configuration parser reported `config ok`.
- Live sources matched the checkout baseline before focused deployment. Saved
  settings are not rewritten, so the current edge and personal Alt+X toggle
  remap remain as chosen. The running Quickshell instance logged “Reloading
  configuration...” and “Configuration Loaded” at 14:30:24 after deployment.
- Physical compositor input/hotplug and an interactive visual check of the
  running desktop are not established by these offscreen tests. Native save/recovery completion limitations found in
  Phase 1 remain recorded in `panel-configuration.md`.
