# pxe-boot — Fedora Kinoite を LAN から PXE + Kickstart でインストールする

QNAP NAS（Container Station / docker compose）上で動く最小構成の PXE サーバー。
**ルータの DHCP は変更しない**（dnsmasq の proxyDHCP で PXE 情報だけ追加配布）。UEFI 専用。

```
クライアント (UEFI, 内蔵 NIC)            NAS (network_mode: host)
  DHCP discover ──────────────▶ ルータ(IP を配る) + dnsmasq(proxy: "BOOTX64.EFI を tftp で")
  tftp BOOTX64.EFI/grubx64.efi/grub.cfg ─▶ dnsmasq(tftp-root=./tftp)
  http /kinoite (stage2 = install.img、その中に ostree repo), /ks/fedora-kinoite.ks ─▶ nginx(./http)
```

Kickstart 本体は [dotfiles](https://github.com/nagata1634/dotfiles) の `bootstrap/fedora-kinoite.ks`。
OS 層はここで、ユーザー環境（設定・Flatpak・KDE 設定のスナップショット）は初回ログイン後の
`install.sh` が作る（2 層）。

## 準備（PC 側で実行。展開と同期は setup-iso.sh がやる）

QNAP は BusyBox で loop mount や ostree が無いため、ISO の展開は PC で行い rsync で NAS へ送る。

```sh
cp -n .env.example .env && vi .env                       # NAS_HOST / LAN_SUBNET / PXE_IFACE / NAS_SSH / NAS_DIR
curl -LO https://download.fedoraproject.org/pub/fedora/linux/releases/44/Kinoite/x86_64/iso/Fedora-Kinoite-ostree-x86_64-44-1.7.iso
curl -LO https://download.fedoraproject.org/pub/fedora/linux/releases/44/Kinoite/x86_64/iso/Fedora-Kinoite-44-1.7-x86_64-CHECKSUM
./setup-iso.sh ~/Downloads/Fedora-Kinoite-ostree-x86_64-44-1.7.iso   # 検証→展開→Kickstart 置換→NAS へ同期
# 起動（QNAP の docker は PATH に無いのでフルパス。DOCKER_CONFIG は QNAP 固有の罠対策）
ssh qnap-yuuya 'export DOCKER_CONFIG=/tmp/.docker-pxe; cd /share/CACHEDEV1_DATA/Container/pxe-boot && /share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker compose up -d'
```

## 動作確認（クライアント側から）

```sh
curl -sI http://NAS_HOST/ks/fedora-kinoite.ks | head -1        # 200
curl -s  http://NAS_HOST/kinoite/images/install.img -o /dev/null -w '%{http_code}\n'
tftp NAS_HOST -c get BOOTX64.EFI                                 # 取れれば OK（tftp-hpa 等）
ssh qnap-yuuya '/share/CACHEDEV1_DATA/.qpkg/container-station/bin/docker logs pxe-dnsmasq --tail 20'   # proxyDHCP 応答
```

## クライアント（ThinkPad）

- UEFI 設定で Network Boot（IPv4 PXE）を有効化、**内蔵 Ethernet** に LAN ケーブル（ドックの USB NIC は
  ファームウェアが PXE 非対応のことがある）
- 起動時に F12 → PXE → GRUB メニューで「自動インストール」を選ぶ
- **ディスクは全消去される**。事前に `backup-check` が OK（Pika の最終成功が 24h 以内）であることを確認し、Pika で「今すぐバックアップ」を 1 回
- 途中で対話入力が 2 つ: LUKS パスフレーズ、初回起動のユーザー作成（Plasma Setup）
- ログイン後、案内に従って `curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash`

## 注意

- Secure Boot は Fedora の shim（`BOOTX64.EFI`）経由なので有効のままで可
- `inst.stage2` は展開した ISO ディレクトリ（`images/install.img` を含む）を指す。ISO ファイルそのものを
  指す `inst.repo=http://…/x.iso` も可だが、展開しておく方が速い
- ISO を更新したら `setup-iso.sh` を再実行し、Kickstart の `ostreesetup --ref` を ISO の ref に合わせる
- Kinoite の ISO は ostree repo を ISO ルートではなく `images/install.img`（stage2）の中に持つ。Kickstart の
  `ostreesetup` は ISO 同梱の既定と同じ `--url=file:///ostree/repo`。`7z` で ISO を展開しても repo は出てこない（正常）
- ISO（数 GB）と展開物は git 管理外（`.gitignore`）
