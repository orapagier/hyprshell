#!/usr/bin/env bash
# Targeted media setup; run as the desktop user. No desktop config replacement.
set -Eeuo pipefail
MODE=${1:---install}
case "$MODE" in --install|--repositories-only) ;; *) printf 'Usage: bash tools/install_media_fedora.sh [--install|--repositories-only]\n' >&2; exit 2 ;; esac
source /etc/os-release
[[ "$ID" == fedora && "$VERSION_ID" =~ ^[0-9]+$ ]] || { printf 'This helper requires traditional Fedora.\n' >&2; exit 1; }
[[ ! -e /run/ostree-booted ]] || { printf 'Fedora Atomic is not supported by this helper.\n' >&2; exit 1; }
sudo -v
releases=()
for channel in free nonfree; do
    if ! rpm -q "rpmfusion-$channel-release" >/dev/null 2>&1; then
        releases+=("https://mirrors.rpmfusion.org/$channel/fedora/rpmfusion-$channel-release-$VERSION_ID.noarch.rpm")
    fi
done
if ((${#releases[@]})); then sudo dnf install -y "${releases[@]}"; fi
[[ "$MODE" != --repositories-only ]] || exit 0

# Replace only the restricted counterparts. Do not use broad --allowerasing.
if rpm -q libavcodec-free >/dev/null 2>&1; then
    sudo dnf swap -y libavcodec-free libavcodec-freeworld
fi
if rpm -q libva-intel-media-driver >/dev/null 2>&1; then
    sudo dnf swap -y libva-intel-media-driver intel-media-driver
fi
sudo dnf install -y --setopt=install_weak_deps=False ffmpeg-free libavcodec-freeworld intel-media-driver libva-utils
if ! ffmpeg -hide_banner -decoders 2>/dev/null | awk '$2 == "hevc" { found=1 } END { exit !found }'; then
    printf 'HEVC software decoder verification failed.\n' >&2
    exit 1
fi
printf 'Media packages installed; restart media apps. Run vainfo in the desktop session to verify GPU decoding.\n'
