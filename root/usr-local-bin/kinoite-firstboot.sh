#!/bin/bash
# 初回起動で root 層を揃える（Kickstart %post では rpm-ostree レイヤも flatpak も使えないため）。
# kinoite-firstboot.service から 1 回だけ実行され、終わると再起動する。
#   1) RPM Fusion（intel-media-driver 用）
#   2) rpm-ostree: ベースの libva-intel-media-driver を外し、packages.txt のレイヤを一括で入れる
#   3) Flatpak（flathub、system）: flatpaks.txt
#   4) docker-compose（podman compose の provider）を /usr/local/bin に
set -euo pipefail
D=/usr/local/share/kinoite-firstboot
DONE=/var/lib/kinoite-firstboot.done
log() { echo ":: $*"; }

pkgs() { grep -vE '^\s*#|^\s*$' "$1" | awk '{print $1}'; }

if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
  log "RPM Fusion"
  rpm-ostree install --idempotent \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
fi

log "rpm-ostree レイヤ"
mapfile -t P < <(pkgs "$D/packages.txt")
if rpm -q libva-intel-media-driver >/dev/null 2>&1; then
  rpm-ostree override remove libva-intel-media-driver $(printf -- '--install %s ' "${P[@]}")
else
  rpm-ostree install --idempotent "${P[@]}"
fi

log "Flatpak"
flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --system --noninteractive flathub $(pkgs "$D/flatpaks.txt") || true

log "docker-compose"
tag="$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4)"
curl -fsSL "https://github.com/docker/compose/releases/download/$tag/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

touch "$DONE"
log "完了。レイヤ反映のため再起動"
systemctl reboot
