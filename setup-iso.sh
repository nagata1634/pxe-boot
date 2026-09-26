#!/usr/bin/env bash
# Kinoite ISO を http/ と tftp/ に展開する（NAS 上で実行。root 不要だが loop mount に sudo が要る場合あり）。
#   ./setup-iso.sh /path/to/Fedora-Kinoite-ostree-x86_64-44-1.x.iso
# 展開後:
#   http/kinoite/            ISO 全体（images/install.img = inst.stage2、ostree/repo = ostreesetup の url）
#   tftp/BOOTX64.EFI, grubx64.efi   ISO の EFI/BOOT から（shim + grub、Secure Boot 可）
#   tftp/kinoite/vmlinuz, initrd.img
#   http/ks/                 Kickstart（dotfiles の bootstrap/fedora-kinoite.ks を NAS_HOST 置換して置く）
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO="${1:?usage: $0 <Kinoite ISO>}"
[ -f "$HERE/.env" ] && . "$HERE/.env"
: "${NAS_HOST:?.env に NAS_HOST を書いてください}"
MNT="$(mktemp -d)"
cleanup() { mountpoint -q "$MNT" && { umount "$MNT" 2>/dev/null || sudo umount "$MNT"; }; rmdir "$MNT"; }
trap cleanup EXIT
mount -o loop,ro "$ISO" "$MNT" 2>/dev/null || sudo mount -o loop,ro "$ISO" "$MNT"

mkdir -p "$HERE/http/kinoite" "$HERE/tftp/kinoite" "$HERE/http/ks"
echo ":: ISO を展開中（数 GB、時間がかかる）"
rsync -a --delete "$MNT/" "$HERE/http/kinoite/"
cp "$MNT/EFI/BOOT/BOOTX64.EFI" "$MNT/EFI/BOOT/grubx64.efi" "$HERE/tftp/"
cp "$MNT/images/pxeboot/vmlinuz" "$MNT/images/pxeboot/initrd.img" "$HERE/tftp/kinoite/"
REF="$(ostree --repo="$HERE/http/kinoite/ostree/repo" refs 2>/dev/null | head -1 || true)"
sed -e "s|@NAS_HOST@|$NAS_HOST|g" "$HERE/tftp/grub.cfg.tmpl" > "$HERE/tftp/grub.cfg"

if [ -f "$HERE/ks/fedora-kinoite.ks" ]; then
  sed -e "s|NAS_HOST|$NAS_HOST|g" "$HERE/ks/fedora-kinoite.ks" > "$HERE/http/ks/fedora-kinoite.ks"
fi
echo ":: 完了。ostree ref: ${REF:-（ostree コマンドが無いため未確認。ISO の ostree/repo/refs/heads/ を参照）}"
echo "   Kickstart の ostreesetup --ref がこれと一致しているか確認すること"
