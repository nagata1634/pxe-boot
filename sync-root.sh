#!/usr/bin/env bash
# ks/ と root/ だけを NAS へ同期する（ISO の再展開なし）。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; . "$HERE/.env"
mkdir -p "$HERE/http/ks" "$HERE/http/root"
sed -e "s|NAS_HOST|$NAS_HOST|g" "$HERE/ks/fedora-kinoite.ks" > "$HERE/http/ks/fedora-kinoite.ks"
rsync -a --delete "$HERE/root/" "$HERE/http/root/"
rsync -a --delete "$HERE/http/ks/" "${NAS_SSH:-qnap-yuuya}:${NAS_DIR:-/share/CACHEDEV1_DATA/Container/pxe-boot}/http/ks/"
rsync -a --delete "$HERE/http/root/" "${NAS_SSH:-qnap-yuuya}:${NAS_DIR:-/share/CACHEDEV1_DATA/Container/pxe-boot}/http/root/"
rsync -a "$HERE/nginx.conf" "${NAS_SSH:-qnap-yuuya}:${NAS_DIR:-/share/CACHEDEV1_DATA/Container/pxe-boot}/"
echo "synced: ks/ root/ nginx.conf"
