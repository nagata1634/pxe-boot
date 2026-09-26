#!/bin/sh
# pxe-dnsmasq コンテナの起動スクリプト。.env の値から dnsmasq.conf を組み立てて前面で起動する。
# proxyDHCP + TFTP のみ（DNS 無効、通常の DHCP はルータのまま）。UEFI x86_64 だけを相手にする。
set -eu
: "${LAN_SUBNET:?}" "${NAS_HOST:?}"
apk add --no-cache dnsmasq >/dev/null
{
  echo "port=0"
  echo "log-dhcp"
  if [ -n "${PXE_IFACE:-}" ]; then echo "interface=$PXE_IFACE"; echo "bind-interfaces"; fi
  echo "dhcp-range=$LAN_SUBNET,proxy"
  echo "enable-tftp"
  echo "tftp-root=/tftp"
  echo "dhcp-match=set:efi-x86_64,option:client-arch,7"
  echo "dhcp-match=set:efi-x86_64,option:client-arch,9"
  echo "dhcp-match=set:bios,option:client-arch,0"
  echo "pxe-service=tag:efi-x86_64,x86-64_efi,\"Fedora Kinoite (UEFI)\",BOOTX64.EFI"
  echo "pxe-service=tag:bios,x86PC,\"BIOS is not supported; use UEFI\","
  echo "dhcp-boot=tag:efi-x86_64,BOOTX64.EFI,,$NAS_HOST"
} > /etc/dnsmasq.conf
echo ":: dnsmasq.conf"; cat /etc/dnsmasq.conf
exec dnsmasq --no-daemon --conf-file=/etc/dnsmasq.conf --log-dhcp
