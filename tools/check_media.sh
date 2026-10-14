#!/usr/bin/env bash
# Verify software fallback codecs on either supported distribution.
set -Eeuo pipefail
for codec in h264 hevc; do
    if ! ffmpeg -hide_banner -decoders 2>/dev/null | awk -v codec="$codec" '$2 == codec { found=1 } END { exit !found }'; then
        printf '%s software decoder verification failed.\n' "$codec" >&2
        exit 1
    fi
done
