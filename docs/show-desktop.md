# Show Desktop

Settings → Hyprpane & panels → Hyprdock or Hyprbar → **Show Desktop shortcut**
adds an optional desktop button. It defaults off and does not alter saved pins,
status-item selections, workspace scopes or existing shortcuts. Both app panels
share one controller through `ApplicationService`.

Click to hide ordinary windows on that output's active numbered workspace,
including pinned windows on that output. Click again to restore the saved set;
restoration can be requested from either panel. Newly opened windows are not
added to the hidden set. Close an open special workspace before using Show
Desktop. The existing Super+H / Super+Shift+H minimized stack is independent.

The helper uses a dedicated `special:hyprshell-desktop` workspace with Hyprland's
[window move, pin and fullscreen dispatchers](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/config/lua/bindings/LuaBindingsDispatchers.cpp).
It writes a private, locked, atomic recovery journal before changing any window,
under `${XDG_STATE_HOME:-$HOME/.local/state}/hyprshell/show-desktop.json`.
The journal survives shell/helper restarts and is excluded from configuration
sync. It contains identities and geometry, not window titles or document contents.

Ordinary windows return to their recorded workspaces. Pinned windows return to
the original output's current workspace, since pinning follows that output's
active workspace. Floating geometry follows the output position and is clamped
to fit a smaller destination. Fullscreen state is restored. A closed window or
an address reused by a different process is skipped. Manually recovered ordinary
windows keep their chosen workspaces. If the source output disappears, restoration
uses the surviving original workspace or an available output's active workspace.
Tiled windows rejoin the compositor layout; exact split-tree reconstruction is
not promised.

A failed hide attempts rollback. A partial restore retains its journal for a
retry; the button and Apps & windows offer **Restore desktop windows**. Errors
open Apps & windows with the recovery message. Recovery works even when the
desktop shortcut is subsequently disabled:

```bash
python3 "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/settings/show_desktop.py" restore
```

The running shell also exposes `bar.restoreDesktop` over its existing IPC.
If a journal is damaged or untracked parked windows exist, keep the journal and
recover individual windows through Apps & windows → Move, or open the dedicated
special workspace explicitly. Do not delete a journal to retry hiding windows.

`tests/test_show_desktop.py` covers rollback, retry after partial restoration,
restart, closed/reused identities, output loss, geometry and session boundaries.
`tests/test_show_desktop_ui.py` checks that a failed toggle offers explicit Restore
instead of accidentally hiding again. `tst_Dock.qml` covers the optional entry
on all four edges. The live session verifier exercises the actual production
button/controller and real pinned/fullscreen windows; see
[panel coexistence](panel-coexistence.md).
