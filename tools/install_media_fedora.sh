#!/usr/bin/env bash
# Hardware-selected media setup; no desktop config replacement.
set -Eeuo pipefail
MODE=${1:---install}
case "$MODE" in --install|--repositories-only|--download-only) ;; *) printf 'Usage: bash tools/install_media_fedora.sh [--install|--repositories-only|--download-only]\n' >&2; exit 2 ;; esac
[[ $# -le 2 && ( -z "${2:-}" || "$2" == --plan-stdin ) ]] || { printf 'Invalid media setup arguments\n' >&2; exit 2; }
source /etc/os-release
[[ "$ID" == fedora && "$VERSION_ID" =~ ^[0-9]+$ ]] || { printf 'This helper requires traditional Fedora.\n' >&2; exit 1; }
[[ ! -e /run/ostree-booted ]] || { printf 'Fedora Atomic is not supported by this helper.\n' >&2; exit 1; }
HELPER_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
sudo -v
releases=()
for channel in free nonfree; do
    if ! rpm -q "rpmfusion-$channel-release" >/dev/null 2>&1; then
        releases+=("https://mirrors.rpmfusion.org/$channel/fedora/rpmfusion-$channel-release-$VERSION_ID.noarch.rpm")
    fi
done
if ((${#releases[@]})); then sudo dnf install -y "${releases[@]}"; fi
[[ "$MODE" != --repositories-only ]] || exit 0

if [[ "${2:-}" == --plan-stdin ]]; then
    selection=$(python3 "$HELPER_DIR/system_plan.py" --read-plan --format media)
else
    selection=$(python3 "$HELPER_DIR/hardware_plan.py" --distro fedora --format media)
    python3 "$HELPER_DIR/hardware_plan.py" --distro fedora --format summary
fi
media=()
if [[ -n "$selection" ]]; then mapfile -t media <<< "$selection"; fi
options=(-y --setopt=install_weak_deps=False)
if [[ "$MODE" == --download-only ]]; then options+=(--downloadonly); fi

# Freeworld complements libavcodec-free; libavformat-free still needs Fedora's
# exact-version package. Swap only mutually exclusive acceleration drivers.
packages=(ffmpeg-free libavcodec-freeworld libva-utils)
if rpm -q ffmpeg >/dev/null 2>&1; then packages=(ffmpeg libavcodec-freeworld libva-utils); fi
for package in "${media[@]}"; do
    counterpart=
    case "$package" in
        intel-media-driver) counterpart=libva-intel-media-driver ;;
        mesa-va-drivers-freeworld) counterpart=mesa-va-drivers ;;
    esac
    if [[ -n "$counterpart" ]] && rpm -q "$counterpart" >/dev/null 2>&1; then
        sudo dnf swap "${options[@]}" "$counterpart" "$package"
        # A download-only swap leaves the old driver installed; don't ask a
        # second transaction to install its conflicting counterpart yet.
        if [[ "$MODE" == --download-only ]]; then continue; fi
    fi
    packages+=("$package")
done
missing=()
for package in "${packages[@]}"; do
    if rpm -q --whatprovides "$package" >/dev/null 2>&1; then
        printf 'Media package present: %s\n' "$package"
    else
        missing+=("$package")
    fi
done
if ((${#missing[@]})); then sudo dnf install "${options[@]}" "${missing[@]}"; fi
[[ "$MODE" != --download-only ]] || exit 0
for codec in h264 hevc; do
    if ! ffmpeg -hide_banner -decoders 2>/dev/null | awk -v codec="$codec" '$2 == codec { found=1 } END { exit !found }'; then
        printf '%s software decoder verification failed.\n' "$codec" >&2
        exit 1
    fi
done
printf 'Media packages ready; restart media apps. Run vainfo in the desktop session to verify GPU decoding.\n'
