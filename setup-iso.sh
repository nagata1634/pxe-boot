#!/usr/bin/env bash
# Kinoite ISO を展開して http/ と tftp/ を作り、NAS へ rsync する。**PC 側で実行**する
# （QNAP は BusyBox で loop mount や ostree が無いため、展開は 7z で PC 上で行う）。
#   ./setup-iso.sh <Kinoite ISO> [<Kickstart>]
# 生成物:
#   http/kinoite/            ISO 全体（images/install.img = inst.stage2、ostree/repo = ostreesetup の url）
#   tftp/BOOTX64.EFI, grubx64.efi   ISO の EFI/BOOT から（shim + grub、Secure Boot 可）
#   tftp/kinoite/vmlinuz, initrd.img、tftp/grub.cfg（@NAS_HOST@ 置換）
#   http/ks/fedora-kinoite.ks（NAS_HOST 置換）
# .env の NAS_HOST / NAS_SSH / NAS_DIR を使う。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="${1:?usage: $0 <Kinoite ISO> [<Kickstart>]}"
KS="${2:-$HOME/.dotfiles/bootstrap/fedora-kinoite.ks}"
[ -f "$HERE/.env" ] && . "$HERE/.env"
: "${NAS_HOST:?.env に NAS_HOST を書いてください}"
NAS_SSH="${NAS_SSH:-qnap-yuuya}"
NAS_DIR="${NAS_DIR:-/share/CACHEDEV1_DATA/Container/pxe-boot}"
command -v 7z >/dev/null || { echo "7z が必要です（p7zip）" >&2; exit 1; }

if [ -f "$ISO.sha256" ] || ls "$(dirname "$ISO")"/*CHECKSUM >/dev/null 2>&1; then
  echo ":: SHA256 を照合"
  ( cd "$(dirname "$ISO")" && grep -h "$(basename "$ISO")" ./*CHECKSUM 2>/dev/null | sed -E 's/^SHA256 \((.*)\) = (.*)$/\2  \1/' | sha256sum -c --quiet ) && echo "   OK"
fi

mkdir -p "$HERE/http/kinoite" "$HERE/tftp/kinoite" "$HERE/http/ks"
echo ":: ISO を展開（7z、数分）"
7z x -y -o"$HERE/http/kinoite" "$ISO" >/dev/null
cp "$HERE/http/kinoite/EFI/BOOT/BOOTX64.EFI" "$HERE/http/kinoite/EFI/BOOT/grubx64.efi" "$HERE/tftp/"
cp "$HERE/http/kinoite/images/pxeboot/vmlinuz" "$HERE/http/kinoite/images/pxeboot/initrd.img" "$HERE/tftp/kinoite/"
sed -e "s|@NAS_HOST@|$NAS_HOST|g" "$HERE/tftp/grub.cfg.tmpl" > "$HERE/tftp/grub.cfg"
sed -e "s|NAS_HOST|$NAS_HOST|g" "$KS" > "$HERE/http/ks/fedora-kinoite.ks"
REF="$(ls "$HERE/http/kinoite/ostree/repo/refs/heads/fedora/"*/x86_64/ 2>/dev/null | head -1 || true)"
echo ":: ostree ref: ${REF:-不明}  ← Kickstart の ostreesetup --ref と一致しているか確認"
grep -n "ostreesetup" "$HERE/http/ks/fedora-kinoite.ks" | head -1

echo ":: NAS へ同期: $NAS_SSH:$NAS_DIR"
ssh "$NAS_SSH" "mkdir -p '$NAS_DIR'"
rsync -a --delete --info=progress2 "$HERE/http/" "$NAS_SSH:$NAS_DIR/http/"
rsync -a --delete "$HERE/tftp/" "$NAS_SSH:$NAS_DIR/tftp/"
rsync -a "$HERE/docker-compose.yml" "$HERE/dnsmasq.conf.tmpl" "$HERE/nginx.conf" "$HERE/.env" "$NAS_SSH:$NAS_DIR/"
echo ":: 完了。起動: ssh $NAS_SSH 'cd $NAS_DIR && \$DOCKER compose up -d'（README 参照）"
