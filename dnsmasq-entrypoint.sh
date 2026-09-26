#!/bin/sh
# pxe-dnsmasq コンテナの起動スクリプト。テンプレートに .env の値を埋めて dnsmasq を前面で起動する。
set -eu
: "${LAN_SUBNET:?}" "${NAS_HOST:?}"
apk add --no-cache dnsmasq >/dev/null
IFACE_LINE=""
[ -n "${PXE_IFACE:-}" ] && IFACE_LINE="interface=$PXE_IFACE
bind-interfaces"
sed -e "s|@LAN_SUBNET@|$LAN_SUBNET|g" -e "s|@NAS_HOST@|$NAS_HOST|g" -e "s|@IFACE_LINE@|$IFACE_LINE|" \
    /etc/dnsmasq.conf.tmpl > /etc/dnsmasq.conf
echo ":: dnsmasq.conf"; grep -vE '^\s*(#|$)' /etc/dnsmasq.conf
exec dnsmasq --no-daemon --conf-file=/etc/dnsmasq.conf --log-dhcp
