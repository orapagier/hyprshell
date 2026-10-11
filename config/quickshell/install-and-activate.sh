#!/usr/bin/env bash
# Run in the desktop terminal after installing the repository configs.
set -euo pipefail
config="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
if ! hyprctl -j monitors >/dev/null 2>&1; then
    printf 'Run this command in a terminal inside your Hyprland desktop session.\n' >&2
    exit 1
fi
if ! command -v quickshell >/dev/null && ! command -v qs >/dev/null; then
    python3 - "$config" <<'PY'
import subprocess, sys
sys.path.insert(0, sys.argv[1] + '/settings')
from system_packages import install_command
subprocess.run(install_command(['quickshell']), check=True)
PY
fi
shell_bin=$(command -v quickshell || command -v qs)
# Stop this shell even when an existing instance was launched from a different path.
shell_id=$(sed -n 's/^\/\/@ pragma ShellId //p' "$config/shell.qml")
while IFS= read -r instance_id; do
    "$shell_bin" kill --id "$instance_id" 2>/dev/null || true
done < <("$shell_bin" list --all --json | awk -F '"' -v expected="$shell_id" '
    /"id":/ { instance = $4 }
    /"shell_id":/ && $4 == expected { print instance }
')
"$shell_bin" kill --path "$config" 2>/dev/null || true
"$HOME/.local/bin/start-quickshell-bar" --require-quickshell
printf 'Hyprshell is active, including the notification inbox.\n'
