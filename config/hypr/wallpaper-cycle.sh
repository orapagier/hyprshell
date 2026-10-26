#!/usr/bin/env bash
# Cycle wallpapers in ~/Pictures/Wallpapers with awww (successor of swww).
# Usage: wallpaper-cycle.sh [next|prev]  (default: next)
set -euo pipefail

WALL_DIR="$HOME/Pictures/Wallpapers"
STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/awww-wallpaper-index"
MODE="${1:-next}"
mkdir -p -- "$(dirname -- "$STATE_FILE")"
[[ $MODE == next || $MODE == prev ]] || exit 2
# Serialize rapid shortcut presses so each successful transition advances once.
exec 9>"$STATE_FILE.lock"
flock 9

[[ -d $WALL_DIR ]] || exit 0
mapfile -d '' -t WALLS < <(find "$WALL_DIR" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 | sort -z)

if [ "${#WALLS[@]}" -eq 0 ]; then
    exit 0
fi

# Make sure the daemon is up
if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    awww-daemon 9>&- &
fi
ready=false
for (( attempt=0; attempt<50; attempt++ )); do
    if awww query >/dev/null 2>&1; then ready=true; break; fi
    sleep 0.1
done
$ready || { printf 'hyprshell: wallpaper daemon did not become ready\n' >&2; exit 1; }

idx="$(cat "$STATE_FILE" 2>/dev/null || true)"
# Bound untrusted/stale cache values before shell arithmetic (including octal
# strings and integers too large for the shell).
if [[ $idx =~ ^[0-9]{1,9}$ ]]; then
    idx=$((10#$idx))
    (( idx < ${#WALLS[@]} )) || idx=-1
else
    idx=-1
fi

if [ "$MODE" = "prev" ]; then
    if (( idx < 0 )); then idx=${#WALLS[@]}; fi
    idx=$(( (idx - 1 + ${#WALLS[@]}) % ${#WALLS[@]} ))
else
    idx=$(( (idx + 1) % ${#WALLS[@]} ))
fi

TRANSITIONS=(grow wave wipe fade outer center)
TRANS="${TRANSITIONS[$RANDOM % ${#TRANSITIONS[@]}]}"

awww img "${WALLS[$idx]}" --transition-type "$TRANS" --transition-step 90 --transition-fps 60
# A failed transition must leave the previous index intact.
echo "$idx" > "$STATE_FILE"
