#!/bin/bash
# 設置先: /usr/local/bin/usb-wakeup.sh（= /var/usrlocal/bin。Atomic で /usr が
# 読み取り専用のため、root が書ける唯一の実質的な bin 置き場）
# 起動元: usb-wakeup.service（sleep.target の前後で ExecStart/ExecStop）
#
# **`/etc/systemd/system-sleep/` に置いてはいけない。** systemd が見るのは
# `/usr/lib/systemd/system-sleep/` だけで、/etc 側は無視される（systemd 259 で確認）。
# よくある誤解で、既存の trackpad-usb-reset.sh はこれが原因で一度も実行されていない。
# Atomic では /usr に書けないので、フックではなく unit で sleep.target に紐付ける。
#
# 目的は 4 つ。
#
# 1) 指定した HID を「機器の identity (VID:PID)」から root hub まで遡って
#    サスペンド復帰源にする。USB の remote wakeup は経路上のハブが全て
#    有効でないと root controller に届かないが、この機材は全機器がドック 1 台に
#    ぶら下がりハブを 3 段挟む。ポート番号で書くと挿し替えで壊れるため、
#    毎回サスペンド直前に「その時点の経路」を計算する。
#
# 2) Goodix 指紋リーダー (27c6:6594) をサスペンド中だけバスから外す。
#    この機器はバス停止と同時に切断され、その port status change が
#    root hub の remote wakeup を叩く。結果「サスペンドした 1〜2 秒後に
#    勝手に復帰する」状態になる（2026-08-30 に実測で確定。ポートを落とすと
#    33 秒眠れ、キーボードで復帰できた）。
#
# 3) 復帰直後に USB / DRM の udev change イベントを再発火させる。
#    2026-09-14、5.5 日間の長時間サスペンドから復帰した際、ドック配下十数台が
#    一斉に再列挙され、外部キーボードが無反応・外部ディスプレイ 2 枚が
#    「connected/enabled」のまま無表示という状態が発生した。手動で
#    `udevadm trigger --action=change --subsystem-match=usb` と
#    `--subsystem-match=drm` を打つと復旧したため、post 側で毎回自動実行する。
#    ドック非接続時（armed=0）でも安全な no-op なので無条件に実行する。
#
# 4) KVM切替器がWindows側を選択している状態でサスペンドすると、ドック配下の
#    機器(REALFORCE等)がUSB的に消えており、2)の経路計算が「対象なし」で
#    スキップされ、復帰源が一切組まれない(2026-09-14に発覚。5.5日間ドック
#    無しで放置後、KVMをLinux側に戻して外部キーボードを叩いても内蔵キーボード
#    等でしか起こせなかった)。ただし KVM 切替時もこの物理ポートに常時挿さって
#    いる上流ハブ(3-1, GenesysLogic 05e3:0610。切替時のdisconnectログに
#    3-1自体は一度も出てこない)は生き残っているため、そこだけは配下に何も
#    無くても常時 wakeup を有効化しておく。KVM を Linux 側へ切り替えた瞬間の
#    ポート connect イベントが root hub まで届くことを狙っているが、
#    ハードウェアが「配下無しのハブでの connect wakeup」を実際に伝搬するかは
#    未検証(次回のKVM切替+サスペンド運用で要確認)。
#
# systemd-sleep 引数: $1=pre|post  $2=suspend|hibernate|...  root で実行される。

# 復帰源にしたい機器。ここを増減させるときは 1 台ずつテストすること。
#
# Magic Trackpad (05ac:0265) は意図的に外してある。バッテリ報告を持つうえ、
# ログイン直後に入力を受け付けない持病があり（USB 層のリセットが要る）、
# 復帰源として信頼できない。同じ日に iPad (05ac:12ab) も fast-charge の
# 再列挙で誤復帰の容疑者になった。Apple 機器はこの用途では使わない方針。
WAKE_DEVICES="0853:0311 056e:0182"   # REALFORCE / IST TrackBall

# サスペンド中だけバスから外す機器。
BLOCK_DEVICES="27c6:6594"                       # Goodix 指紋リーダー（内蔵）

STATE=/run/usb-wakeup.disabled-ports

# KVM切替器の常設アップリンクハブ(3-1)。ラップトップ本体側の物理ポート位置で
# 固定されており、KVMがWindows側を選択していてもここ自体は切断されない。
STATIC_UPSTREAM_PORT=/sys/bus/usb/devices/3-1

# VID:PID から sysfs のデバイスディレクトリを引く（複数該当しうる）
usb_dirs_of() {
  local vid=${1%%:*} pid=${1##*:} d
  for d in /sys/bus/usb/devices/*/; do
    [ -f "$d/idVendor" ] || continue
    [ "$(cat "$d/idVendor" 2>/dev/null)" = "$vid" ] || continue
    [ "$(cat "$d/idProduct" 2>/dev/null)" = "$pid" ] || continue
    echo "${d%/}"
  done
}

# デバイスから root hub まで親を遡って power/wakeup を有効化
enable_chain() {
  local d
  d=$(readlink -f "$1")
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "/sys/devices" ]; do
    if [ -f "$d/idVendor" ] && [ -w "$d/power/wakeup" ]; then
      echo enabled > "$d/power/wakeup" 2>/dev/null
    fi
    d=$(dirname "$d")
  done
}

# デバイスが刺さっている usbN-portM / X-Y-portZ の sysfs を引く
port_of() {
  local target p
  target=$(readlink -f "$1")
  for p in /sys/bus/usb/devices/*/*-port*; do
    [ -e "$p/device" ] || continue
    [ "$(readlink -f "$p/device")" = "$target" ] && { echo "$p"; return; }
  done
}

case "$1" in
  pre)
    # 1. 一旦すべて無効化する。前回の状態や他所で書かれた値を引きずらないため。
    #    注意: USB LAN の Wake-on-LAN もここで無効になる。要るなら個別に戻すこと。
    for w in /sys/bus/usb/devices/*/power/wakeup; do
      echo disabled > "$w" 2>/dev/null
    done

    # 2. 起こしたい機器の経路だけを有効化
    armed=0
    for id in $WAKE_DEVICES; do
      for d in $(usb_dirs_of "$id"); do
        enable_chain "$d"
        armed=1
        logger -t usb-wakeup "wake path enabled for $id ($(basename "$d"))"
      done
    done

    # 2.5. KVM切替器の常設アップリンクハブは、配下に何も無くても
    #      (KVMがWindows側を選択していても)常時 wakeup を有効化しておく。
    #      KVMをLinux側に戻した瞬間のconnectイベントを拾うための保険。
    if [ -w "$STATIC_UPSTREAM_PORT/power/wakeup" ]; then
      echo enabled > "$STATIC_UPSTREAM_PORT/power/wakeup" 2>/dev/null
      logger -t usb-wakeup "static upstream hub $(basename "$STATIC_UPSTREAM_PORT") wakeup force-enabled (KVM passthrough)"
    fi

    # 3. ノイズ源をポートごと落とす。戻す対象を /run に控える。
    #
    # 経路を 1 つも張れなかったとき（＝ドックを外してノート単体で使っているとき）は
    # 何もしない。USB の復帰経路が無いのだから Goodix が port change を上げても
    # 誰も起きず、ポートを落とす意味が無い。落とすと復帰後に指紋リーダーが戻るまで
    # 2 秒ほどかかるので、その代償を払わずに済ませる。
    # 単体運用時の復帰源（蓋 / 内蔵キーボード serio0 / 電源ボタン）は
    # platform デバイスなので、このスクリプトは一切触らない。
    [ "$armed" = "1" ] || { logger -t usb-wakeup "no USB wake device present; skipping"; exit 0; }

    : > "$STATE"
    for id in $BLOCK_DEVICES; do
      for d in $(usb_dirs_of "$id"); do
        p=$(port_of "$d")
        [ -n "$p" ] && [ -w "$p/disable" ] || continue
        echo 1 > "$p/disable" 2>/dev/null || continue
        echo "$p" >> "$STATE"
        logger -t usb-wakeup "port disabled: $(basename "$p") ($id)"
      done
    done
    ;;

  post)
    # 復帰直後、長時間サスペンド後の大量再列挙で USB 入力機器や外部
    # ディスプレイの状態が更新されないまま残るのを防ぐため、udev の
    # change イベントを無条件に再発火させる。ドック非接続時も安全な no-op。
    udevadm trigger --action=change --subsystem-match=usb 2>/dev/null
    udevadm trigger --action=change --subsystem-match=drm 2>/dev/null
    udevadm settle --timeout=5 2>/dev/null
    logger -t usb-wakeup "post-resume udev retrigger (usb, drm) done"

    # pre で落としたポートだけを戻す（device リンクは切れているので控えを使う）
    [ -f "$STATE" ] || exit 0
    while read -r p; do
      [ -n "$p" ] && [ -w "$p/disable" ] || continue
      echo 0 > "$p/disable" 2>/dev/null
      logger -t usb-wakeup "port re-enabled: $(basename "$p")"
    done < "$STATE"
    rm -f "$STATE"
    ;;
esac

exit 0
