# Comprehensive theming: future implementation plan



Status: deferred proposal. Saved on 2026-10-14 at the user's request.
Implementation is not authorized yet; the user may approve or revise this plan
when returning to the feature. No desktop configuration changes accompany it.

## Intended experience

Hyprshell supports portable community theme packages that coordinate desktop,
window, and supported application appearance. Each theme retains its own personal
customizations, including wallpaper and workspace-specific Hyprpane visibility.

Super + Shift + W opens a stacked theme preview on the focused monitor. Arrow keys
navigate, Enter applies the selected theme, and Escape closes without changes.
Browsing changes the preview only, rather than repeatedly applying desktop themes.

## Existing foundation

The inspected setup already provides application appearance preferences,
configurable Hyprpane styling, workspace-specific bar visibility, wallpaper
handling, and validated settings transactions. Relevant integration points include:

- `config/quickshell/style/Theme.qml` and shell components.
- `config/quickshell/SettingsTheme.qml` and the existing Settings model/store.
- `config/quickshell/settings/theme.py` and `backend.py`.
- `config/hyprshell/settings.json` and `theme.json`.
- `config/hyprshell/hyprland/shortcuts.lua` and generated appearance overrides.
- Wallpaper helpers, lock-screen configuration, installer, recovery, and GitHub sync.

Reinspect these paths, repository status, and live/repository differences before
implementation; this document describes a proposal, not an established schema.

## Theme package format

Use a folder or importable archive with:

- A versioned manifest containing stable ID, name, author, description, license,
  and compatibility requirements.
- Shared palette, typography, spacing, rounding, and transparency.
- Desktop appearance defaults and workspace-specific Hyprpane visibility.
- Wallpaper assets and preview images.
- Optional GTK/Qt assets and supported application palettes.

Provide author documentation, an example package, and a validator. Packages use
declarative settings and supported assets; importing or applying a package does
not execute arbitrary theme scripts. Validate assets and archive paths before use.

## Appearance coverage

| Area | Proposed controls |
| --- | --- |
| Hyprshell | Hyprpane, launcher, menus, notifications, Settings, picker, shared controls |
| Hyprland | Borders, active/inactive colors, rounding, shadows, blur, opacity, gaps, supported animations |
| Wallpaper | Theme default, personal replacement, per-monitor choices |
| Hyprpane | Position, layout, item styling, adaptive colors, workspace visibility |
| Applications | Light/dark preference, GTK/Qt integration, fonts, icons, cursors, supported application palettes |
| Lock screen | Matching colors, typography, wallpaper |

Start explicit application adapters with Kitty and expose a documented extension
interface. Show missing integrations and restart requirements in Settings.

Application-owned styles can override system preferences. Do not promise identical
appearance or immediate updates in every app. GTK, Libadwaita, Qt, and other
toolkits require distinct integration and live verification:

- [Qt platform integration](https://doc.qt.io/qt-6/qpa.html).
- [Libadwaita styles and appearance](https://github.com/GNOME/libadwaita/blob/main/doc/styles-and-appearance.md).

Login and boot appearance are a later explicit extension, with their own apply
step for privileged files rather than changes on every picker selection.

## Stacked picker and shortcuts

- Center the picker on the focused monitor, selected card at the front and
  neighboring cards visible behind it.
- Show wallpaper, palette, sample window, Hyprpane, theme name, and active marker.
- Support arrow navigation, Enter to apply, and Escape to cancel.
- Respect reduced motion and restore keyboard focus on close.
- Apply only after Enter; browsing does not mutate desktop preferences.

Super + Shift + W currently selects the previous wallpaper. Proposed reassignment:
use it for the theme picker, move previous wallpaper to Super + Alt + W, and keep
Super + W for next wallpaper. Keep shortcuts editable and verify conflicts before
implementation. This reassignment remains part of the pending proposal.

## Settings integration

Add a Themes page for browsing, applying, importing, exporting, duplicating, and
removing themes. Support saving the current appearance as a new theme.

Allow editing wallpaper, palette, window styling, Hyprpane configuration, and which
numbered workspaces show Hyprpane. Support resetting individual preferences or all
customizations for a theme. Show missing assets, dependencies, and application
compatibility. Preserve existing appearance controls and connect them to the
active theme's overrides rather than removing controls or behavior.

## Preference resolution and preservation

Resolve appearance in this order:

1. Hyprshell defaults.
2. Theme defaults.
3. User overrides saved for that theme.

Changing Theme A's wallpaper or hiding its bar on workspace 3 affects Theme A.
Switching to Theme B loads B's preferences; returning to A restores A's edits.
Theme updates preserve personal overrides. Define predictable fallbacks for fonts,
icons, and cursors unavailable on another machine.

Keep hardware configuration, shortcuts, default applications, networking, and
unrelated preferences independent of theme switching. The current appearance
becomes the initial Personal theme during migration.

## Coordinated apply and recovery

Create one coordinator that validates resolved appearance, stages generated
configuration, and records the previous appearance before applying changes.
Integrate with existing Settings write serialization and stale-edit detection.
Restore managed configuration after failure and report incomplete runtime
restoration. Provide Revert to previous theme.

Design interrupted-operation recovery across the participating appearance
backends; do not assume multiple file writes and runtime updates are inherently
atomic. Preserve unrelated settings and user-managed configuration blocks.

## Installation, updates, and sync

Ship bundled themes with Hyprshell and keep imported themes in a user theme
directory. Preserve active-theme selection and overrides through updates.

Sync theme preferences and selected portable packages/assets. Explicitly extend
the existing wallpaper policy, which currently tracks only `default.jpg`, for
theme-owned assets. Keep unrelated wallpaper collections outside sync and avoid
exporting machine-specific absolute paths as portable defaults.

## Implementation stages

1. Foundation: package format, validation, migration, override storage, and
   apply/revert coordinator.
2. Desktop integration: shared styling across shell surfaces, Hyprland,
   wallpaper, and locking.
3. User controls: stacked picker, shortcuts, and Settings editor.
4. Application integration and sharing: GTK/Qt adapters, Kitty palette,
   import/export, installer, sync, and author documentation.

## Acceptance checks

- Switching themes restores each theme's wallpaper and workspace bar choices.
- Shell surfaces and compositor appearance consistently consume the active theme.
- Picker navigation, cancellation, application, focus, and reduced motion work.
- Existing appearance controls and unrelated settings retain their behavior.
- Invalid packages, missing assets, and absent dependencies produce useful results.
- Concurrent edits, interrupted application, rollback, and revert are exercised.
- Theme updates preserve overrides; import/export and sync retain portable assets.
- Live GTK/Qt and Kitty checks distinguish immediate changes from app-restart needs.
- Review all implementation diffs and reconcile live/repository copies before
  deployment; isolated tests do not establish live application compatibility.

## Next action

Wait for the user to revisit and approve or modify this proposal before beginning
implementation. Saving this plan does not authorize feature code, shortcut
changes, theme activation, or deployment.
