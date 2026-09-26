# pxe-boot — Fedora Kinoite を LAN から PXE + Kickstart でインストールする

QNAP NAS（Container Station / docker compose）上で動く最小構成の PXE サーバー。
**ルータの DHCP は変更しない**（dnsmasq の proxyDHCP で PXE 情報だけ追加配布）。UEFI 専用。

```
クライアント (UEFI, 内蔵 NIC)            NAS (network_mode: host)
  DHCP discover ──────────────▶ ルータ(IP を配る) + dnsmasq(proxy: "BOOTX64.EFI を tftp で")
  tftp BOOTX64.EFI/grubx64.efi/grub.cfg ─▶ dnsmasq(tftp-root=./tftp)
  http /kinoite (stage2, ostree repo), /ks/fedora-kinoite.ks ─▶ nginx(./http)
```

Kickstart 本体は [dotfiles](https://github.com/nagata1634/dotfiles) の `bootstrap/fedora-kinoite.ks`。
OS 層はここで、ユーザー環境（設定・Flatpak・KDE 設定のスナップショット）は初回ログイン後の
`install.sh` が作る（2 層）。

## 準備（NAS 上）

```sh
# 1. 配置（claude-hub と同じ場所の流儀）
ssh qnap-yuuya 'mkdir -p /share/CACHEDEV1_DATA/Container/pxe-boot'
scp -r docker-compose.yml dnsmasq.conf.tmpl nginx.conf setup-iso.sh tftp .env.example qnap-yuuya:/share/CACHEDEV1_DATA/Container/pxe-boot/
# 2. .env（NAS の IP、サブネット）
ssh qnap-yuuya 'cd /share/CACHEDEV1_DATA/Container/pxe-boot && cp -n .env.example .env && vi .env'
# 3. Kickstart と ISO を置いて展開
scp ~/.dotfiles/bootstrap/fedora-kinoite.ks qnap-yuuya:/share/CACHEDEV1_DATA/Container/pxe-boot/ks/
scp ~/Downloads/Fedora-Kinoite-ostree-x86_64-44-*.iso qnap-yuuya:/share/CACHEDEV1_DATA/Container/pxe-boot/
ssh qnap-yuuya 'cd /share/CACHEDEV1_DATA/Container/pxe-boot && ./setup-iso.sh Fedora-Kinoite-ostree-x86_64-44-*.iso'
# 4. 起動（DOCKER_CONFIG は QNAP 固有の罠対策）
ssh qnap-yuuya 'export DOCKER_CONFIG=/tmp/.docker-pxe; cd /share/CACHEDEV1_DATA/Container/pxe-boot && docker compose up -d'
```

## 動作確認（クライアント側から）

```sh
curl -sI http://NAS_HOST/ks/fedora-kinoite.ks | head -1        # 200
curl -s  http://NAS_HOST/kinoite/images/install.img -o /dev/null -w '%{http_code}\n'
tftp NAS_HOST -c get BOOTX64.EFI                                 # 取れれば OK（tftp-hpa 等）
ssh qnap-yuuya 'docker logs pxe-dnsmasq --tail 20'               # 起動時の proxyDHCP 応答が出る
```

## クライアント（ThinkPad）

- UEFI 設定で Network Boot（IPv4 PXE）を有効化、**内蔵 Ethernet** に LAN ケーブル（ドックの USB NIC は
  ファームウェアが PXE 非対応のことがある）
- 起動時に F12 → PXE → GRUB メニューで「自動インストール」を選ぶ
- **ディスクは全消去される**。事前に Pika Backup で `~` を NAS に取ること
- 途中で対話入力が 2 つ: LUKS パスフレーズ、初回起動のユーザー作成（Plasma Setup）
- ログイン後、案内に従って `curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash`

## 注意

- Secure Boot は Fedora の shim（`BOOTX64.EFI`）経由なので有効のままで可
- `inst.stage2` は展開した ISO ディレクトリ（`images/install.img` を含む）を指す。ISO ファイルそのものを
  指す `inst.repo=http://…/x.iso` も可だが、展開しておく方が速い
- ISO を更新したら `setup-iso.sh` を再実行し、Kickstart の `ostreesetup --ref` を ISO の ref に合わせる
- ISO（数 GB）と展開物は git 管理外（`.gitignore`）
