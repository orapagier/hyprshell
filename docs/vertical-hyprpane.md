# Vertical Hyprpane — Phase 2

On Left and Right, Hyprpane shows icons only in circular pills, following the
user's latest 2026-10-16 refinement. This replaces the earlier character-column
layout. The default width is 40 logical pixels; explicit thickness, font/icon
sizes and inside padding still apply. Saved labels remain available in tooltips
and apply again on Top/Bottom, along with the original horizontal radii and media.

Settings → Hyprpane & panels → Layout & spacing → Side panel length offers
Full edge and Compact (`bar.verticalPresentation`, default `edge`). Compact
centers the shorter pane and keeps Top/Center/Bottom groups together. Full edge
keeps their saved alignment, constraining the middle group to prevent overlaps.
Both preserve item ordering, enabled flags, icon visibility, colors, margins and
spacing. Shared group membership remains saved; on side edges its background is
drawn as individual circles. Circular side shapes override custom corner radii
visually; those saved radii apply again on Top/Bottom.

Long content scrolls in the pane with a visible scrollbar. Wheel over status
items, drag, use the scrollbar, or Tab to a control to reveal it. Workspace-wheel
switching and tray scroll actions still work. Tray icons use individual circular hit
areas sized to the pane and stack vertically; keyboard Enter and Menu actions
retain access to activation and context menus. Settings preview hit testing and
drag/drop account for scrolling.

The calendar uses a calendar icon and keeps the saved format/custom label in its
tooltip. Audio, network, Bluetooth and battery show their status icons; values
remain in tooltips and menus. Workspace names become filled/hollow workspace
icons with identifying tooltips. Notification counts appear in the tooltip/inbox,
while the bell color indicates unread items. Tray icons each have a circular pill.
Media has five spectrum bars centered inside its circle, aggregating the existing
bands without changing audio capture. Its complete title or custom label stays
in the tooltip, and hiding its icon still hides the spectrum. Side menus open
inward beside their trigger, remain inside the
available screen area, and scroll long pages. Keyboard focus reveals controls
inside both the pane and menu viewport. Existing Settings card/button actions
are preserved through the menu viewport.

## Reviewed images

These are Qt 6 software-rendered fixtures, not captures of personal notifications
or a physical desktop. They show icon-only controls, the compact spectrum, tray,
an unread bell,
volume, Bluetooth, network, battery, workspace icons and an inward calendar card.

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

## Icon-only follow-up — 2026-10-16

The latest preference supersedes the initial Phase 2 character-column screenshots
and assertions. Updated coverage checks no side labels/digits, intact custom
icons, circular geometry including shared groups/tray, calendar tooltip/actions,
workspace icons, a five-bar spectrum contained within its circle, preserved icon
hiding, overflow and the return of saved labels/radii on horizontal edges.

Follow-up validation: all 193 QML checks passed; all 16 focused vertical checks
also passed at 150% scale. Both updated fixture screenshots were reviewed.
Applied matching live files with backups; the running shell confirmed reload at
14:55:56. Saved settings were not rewritten.
