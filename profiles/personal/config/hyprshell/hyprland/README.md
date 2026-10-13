# Personal desktop configuration

Edit these files to customize the desktop. `../../hypr/hyprland.lua` loads
these sections on every config reload; it is only the entry point.

| File | Settings |
| --- | --- |
| `monitors.lua` | Automatic display fallback |
| `programs.lua` | Default terminal, file manager, and launcher |
| `environment.lua` | Cursor environment and permission examples |
| `appearance.lua` | Borders, gaps, transparency, blur, and animations |
| `layouts.lua` | Tiling layout options and miscellaneous behavior |
| `input.lua` | Keyboard, touchpad, mouse, and gestures |
| `shortcuts.lua` | Default keyboard and mouse shortcuts, including minimize/restore |
| `windows.lua` | App/dialog placement and shell layer effects |
| `startup.lua` | Programs launched when the session starts |

Generated HyprMod settings in `hypr/hyprland-gui.lua` load after these defaults.
Hyprshell Settings overrides in `hyprshell/overrides.lua`, `keybindings.lua`,
and `displays.lua` apply afterward and take precedence. Use the Settings pages
to edit those generated files. For example, a saved browser command overrides
the default Super+B command here.

Validate and reload after editing:

```bash
Hyprland --verify-config --config "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
hyprctl reload
hyprctl configerrors
```

The installer restores this directory. Settings sync snapshots this directory
into the checkout along with the desktop entry point.
