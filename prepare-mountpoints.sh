#!/bin/bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || {
    echo "Run this one-time preparation with sudo:" >&2
    echo "  sudo ./prepare-mountpoints.sh" >&2
    exit 1
}

target_user=${SUDO_USER:-}
[ -n "$target_user" ] && [ "$target_user" != root ] || {
    echo "Could not determine the non-root target user from SUDO_USER." >&2
    exit 1
}
target_group=$(id -gn "$target_user")

mountpoints=(
    /home/mauajama/Sayooj
    /mnt/DATA/mauajama/Sayooj
    /home/mauajama/Sayooj_y
    /data/mauajama/Sayooj_y
)

for target in "${mountpoints[@]}"; do
    if mountpoint -q "$target"; then
        echo "Already mounted; leaving unchanged: $target"
        continue
    fi
    install -d -m 0755 "$(dirname "$target")"
    install -d -o "$target_user" -g "$target_group" -m 0755 "$target"
    echo "Prepared $target for $target_user:$target_group"
done
