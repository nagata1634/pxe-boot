# Fedora Kinoite の自動インストール定義（Kickstart）。PXE + HTTP で配る（pxe-boot の nginx）。
#
# 担当分け: OS と root 層（rpm-ostree レイヤ・Flatpak・/etc・/usr/local）はここ（pxe-boot）、
# ~/ の層（symlink・KDE 設定スナップショット等）は初回ログイン後の dotfiles/install.sh。
#
# %post では rpm-ostree レイヤも flatpak も使えない（イメージを deploy した直後の chroot）ため、
# %post は「/etc と /usr/local にファイルを置いて unit を有効化する」までにし、レイヤと Flatpak は
# 初回起動の oneshot（kinoite-firstboot.service）が入れて再起動する。
#
# 機密は一切書かない（公開リポジトリ）: LUKS パスフレーズは対話、ユーザーは初回起動の Plasma Setup。
# NAS_HOST は setup-iso.sh が .env の値に置換する。検証: ksvalidator -v F44 ks/fedora-kinoite.ks

lang ja_JP.UTF-8
keyboard us
timezone Asia/Tokyo --utc
network --bootproto=dhcp --device=link --activate
rootpw --lock

ignoredisk --only-use=nvme0n1
clearpart --all --initlabel --disklabel=gpt
autopart --type=btrfs --encrypted --luks-version=luks2

# ISO の ostree repo は images/install.img（stage2）の中にある。ISO 同梱の既定と同じ指定。
# ref は ISO のバージョンで変わる（setup-iso.sh が表示する）。
ostreesetup --nogpg --osname="fedora" --remote="fedora" --url="file:///ostree/repo" --ref="fedora/44/x86_64/kinoite"

selinux --enforcing
firewall --enabled
reboot

%post --erroronfail --interpreter=/bin/bash
set -euo pipefail
R="http://NAS_HOST/root"   # pxe-boot/root/ を nginx が配る

# ostree remote を公式に向け直す（インストール時は ISO 内の repo、以後は GPG 検証付きの公式）
ostree remote delete fedora || true
ostree remote add --set=gpg-verify=true --set=gpgkeypath=/etc/pki/rpm-gpg/ fedora https://ostree.fedoraproject.org 2>/dev/null \
  || ostree remote add --no-gpg-verify fedora https://ostree.fedoraproject.org

# authselect: Yubikey(u2f) → 指紋 → パスワード
mkdir -p /etc/authselect/custom/yuya-auth
for f in README REQUIREMENTS dconf-db dconf-locks fingerprint-auth nsswitch.conf password-auth postlogin smartcard-auth switchable-auth system-auth; do
  curl -fsSL "$R/authselect/yuya-auth/$f" -o "/etc/authselect/custom/yuya-auth/$f"
done
authselect select custom/yuya-auth with-pam-u2f with-fingerprint with-mdns4 with-silent-lastlog --force

# usb-wakeup: サスペンド前後で USB の復帰源を組み直す（/usr/local = /var/usrlocal）
mkdir -p /usr/local/bin /usr/local/share/kinoite-firstboot
curl -fsSL "$R/usr-local-bin/usb-wakeup.sh" -o /usr/local/bin/usb-wakeup.sh
curl -fsSL "$R/systemd/usb-wakeup.service" -o /etc/systemd/system/usb-wakeup.service
chmod +x /usr/local/bin/usb-wakeup.sh
systemctl enable usb-wakeup.service

# 初回起動 oneshot: RPM Fusion → rpm-ostree レイヤ → Flatpak → docker-compose → 再起動
curl -fsSL "$R/usr-local-bin/kinoite-firstboot.sh" -o /usr/local/bin/kinoite-firstboot.sh
curl -fsSL "$R/systemd/kinoite-firstboot.service" -o /etc/systemd/system/kinoite-firstboot.service
curl -fsSL "$R/packages.txt" -o /usr/local/share/kinoite-firstboot/packages.txt
curl -fsSL "$R/flatpaks.txt" -o /usr/local/share/kinoite-firstboot/flatpaks.txt
chmod +x /usr/local/bin/kinoite-firstboot.sh
systemctl enable kinoite-firstboot.service

# 初回セットアップウィザードは使う（ユーザー作成）。終わったらウィザード側が /etc/plasma-setup-done を置く。

# 初回ログイン時に dotfiles（~/ の層）の適用を促す（~/.dotfiles が clone されたら消える）
cat > /etc/profile.d/zz-dotfiles-hint.sh <<'HINT'
if [ -n "${BASH_VERSION:-}" ] && [ ! -d "$HOME/.dotfiles" ]; then
    printf '\n\033[1;34m::\033[0m dotfiles が未適用です。次を実行してください:\n'
    printf '   curl -fsSL https://raw.githubusercontent.com/nagata1634/dotfiles/main/install.sh | bash\n\n'
fi
HINT
%end
