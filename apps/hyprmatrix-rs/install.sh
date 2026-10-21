#!/usr/bin/env bash
# Install just Hyprmatrix, without changing or reloading the rest of the desktop.
set -euo pipefail
app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$app_dir/../.." && pwd)"
cargo build --release --locked --manifest-path "$app_dir/Cargo.toml"
install -Dm755 "${CARGO_TARGET_DIR:-$app_dir/target}/release/hyprmatrix" "$HOME/.local/bin/hyprmatrix"
install -Dm644 "$repo_dir/assets/applications/hyprmatrix.desktop" "${XDG_DATA_HOME:-$HOME/.local/share}/applications/hyprmatrix.desktop"
config_file="${XDG_CONFIG_HOME:-$HOME/.config}/hyprmatrix/config.toml"
if [[ ! -e "$config_file" ]]; then
    install -Dm644 "$repo_dir/config/hyprmatrix/config.toml" "$config_file"
fi
printf 'Installed Hyprmatrix. Launch: %s/.local/bin/hyprmatrix\n' "$HOME"
