#!/usr/bin/env bash
# Internet Monitoring Agent — .deb yaratuvchi (Ubuntu/Debian).
#
# Foydalanish:
#   sudo apt install -y libgtk-3-dev libsecret-1-dev libjsoncpp-dev \
#                       libayatana-appindicator3-dev ninja-build
#   flutter build linux --release
#   bash installer/linux/deb/build_deb.sh
#
# Natija: build/installer/internet-monitoring-agent_<version>_amd64.deb

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD_OUT="$ROOT/build/linux/x64/release/bundle"
VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)"
PKG_NAME="internet-monitoring-agent"
ARCH="amd64"
OUT_DIR="$ROOT/build/installer"
STAGE="$(mktemp -d)"
DEB_ROOT="$STAGE/${PKG_NAME}_${VERSION}_${ARCH}"

if [ ! -d "$BUILD_OUT" ]; then
  echo "Xato: $BUILD_OUT topilmadi. 'flutter build linux --release' ishlatilsin." >&2
  exit 1
fi

mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$DEB_ROOT/opt/internet-monitoring-agent"
mkdir -p "$DEB_ROOT/usr/share/applications"
mkdir -p "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DEB_ROOT/usr/lib/systemd/user"
mkdir -p "$DEB_ROOT/etc/xdg/autostart"
mkdir -p "$DEB_ROOT/usr/bin"

# PATH ichida `internet-monitoring-agent` buyrug'i bo'lishi uchun symlink.
ln -sf /opt/internet-monitoring-agent/internet "$DEB_ROOT/usr/bin/internet-monitoring-agent"

cp -r "$BUILD_OUT"/* "$DEB_ROOT/opt/internet-monitoring-agent/"
cp "$ROOT/installer/linux/systemd/internet-agent.service" \
   "$DEB_ROOT/usr/lib/systemd/user/internet-agent.service"

# .desktop fayl (menyu uchun)
cat > "$DEB_ROOT/usr/share/applications/internet-monitoring-agent.desktop" <<EOF
[Desktop Entry]
Name=Internet Monitoring Agent
Comment=Authorized education monitoring agent
Exec=/opt/internet-monitoring-agent/internet
Icon=internet-monitoring-agent
Terminal=false
Type=Application
Categories=Network;Utility;
StartupWMClass=internet
EOF

# Auto-start har gal kompyuter yonganda (XDG autostart, har qaysi DE qo'llaydi).
cat > "$DEB_ROOT/etc/xdg/autostart/internet-monitoring-agent.desktop" <<EOF
[Desktop Entry]
Name=Internet Monitoring Agent
Comment=Authorized education monitoring agent (autostart)
Exec=/opt/internet-monitoring-agent/internet --startup-tray
Icon=internet-monitoring-agent
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
StartupWMClass=internet
EOF

# Ikonkani ko'chirish (mavjud bo'lsa)
if [ -f "$ROOT/assets/branding/app_logo.png" ]; then
  cp "$ROOT/assets/branding/app_logo.png" \
     "$DEB_ROOT/usr/share/icons/hicolor/256x256/apps/internet-monitoring-agent.png"
fi

# control fayl
cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${ARCH}
Depends: libgtk-3-0, libsecret-1-0, libayatana-appindicator3-1, scrot, imagemagick, ffmpeg, gnome-screenshot | spectacle | flameshot | grim | xfce4-screenshooter, libglib2.0-bin, x11-apps
Recommends: grim, gnome-screenshot, spectacle, xdg-desktop-portal
Maintainer: E-MMTB <admin@e-mmtb.uz>
Description: Internet Monitoring Agent
 Authorized education monitoring agent for Linux desktops.
 Collects heartbeat, internet speed, installed apps and process
 snapshot for the central admin panel.
EOF

# postinst — agentni user-mode systemd'ga yozish + Wayland'ni o'chirish
# (screen monitoring uchun X11 kerak, Wayland xavfsizlik chegaralari sababli)
cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
chmod +x /opt/internet-monitoring-agent/internet || true

# === X11 majburiy: barcha display manager'larda Wayland'ni o'chirish ===
# Screen capture (scrot, ffmpeg, import) Wayland'da ishlamaydi.
# Bu o'zgartirish keyingi login'dan keyin kuchga kiradi.

WAYLAND_DISABLED=0

# GDM3 (Ubuntu, Debian, Kali)
if [ -f /etc/gdm3/daemon.conf ]; then
    if grep -q "^WaylandEnable=" /etc/gdm3/daemon.conf; then
        sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/daemon.conf
    elif grep -q "^#WaylandEnable=" /etc/gdm3/daemon.conf; then
        sed -i 's/^#WaylandEnable=.*/WaylandEnable=false/' /etc/gdm3/daemon.conf
    else
        # [daemon] sectioniga qo'shish
        if grep -q "^\[daemon\]" /etc/gdm3/daemon.conf; then
            sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm3/daemon.conf
        else
            echo -e "[daemon]\nWaylandEnable=false" >> /etc/gdm3/daemon.conf
        fi
    fi
    WAYLAND_DISABLED=1
    echo "[IMA] GDM3 sozlandi: WaylandEnable=false"
fi

# GDM (Fedora, RHEL, CentOS)
if [ -f /etc/gdm/custom.conf ]; then
    if grep -q "^WaylandEnable=" /etc/gdm/custom.conf; then
        sed -i 's/^WaylandEnable=.*/WaylandEnable=false/' /etc/gdm/custom.conf
    elif grep -q "^#WaylandEnable=" /etc/gdm/custom.conf; then
        sed -i 's/^#WaylandEnable=.*/WaylandEnable=false/' /etc/gdm/custom.conf
    else
        if grep -q "^\[daemon\]" /etc/gdm/custom.conf; then
            sed -i '/^\[daemon\]/a WaylandEnable=false' /etc/gdm/custom.conf
        else
            echo -e "[daemon]\nWaylandEnable=false" >> /etc/gdm/custom.conf
        fi
    fi
    WAYLAND_DISABLED=1
    echo "[IMA] GDM sozlandi: WaylandEnable=false"
fi

# SDDM (KDE Plasma)
if [ -d /etc/sddm.conf.d ] || [ -f /etc/sddm.conf ]; then
    mkdir -p /etc/sddm.conf.d
    cat > /etc/sddm.conf.d/10-internet-agent-x11.conf <<SDDM
[General]
DisplayServer=x11
SDDM
    WAYLAND_DISABLED=1
    echo "[IMA] SDDM sozlandi: DisplayServer=x11"
fi

# LightDM (XFCE, MATE) — odatda X11 default, lekin ehtiyot uchun
if [ -d /etc/lightdm/lightdm.conf.d ]; then
    cat > /etc/lightdm/lightdm.conf.d/10-internet-agent-x11.conf <<LDM
[Seat:*]
greeter-session=lightdm-gtk-greeter
LDM
fi

if [ "$WAYLAND_DISABLED" = "1" ]; then
    echo "[IMA] ============================================"
    echo "[IMA] Screen monitoring uchun X11 yoqildi."
    echo "[IMA] Foydalanuvchi keyingi LOGIN'da X11'da kiradi."
    echo "[IMA] Joriy sessiya hali Wayland'da bo'lishi mumkin."
    echo "[IMA] ============================================"
fi

# Foydalanuvchi qo'lda yoqishi mumkin: systemctl --user enable --now internet-agent.service
exit 0
EOF
chmod 0755 "$DEB_ROOT/DEBIAN/postinst"

# prerm
cat > "$DEB_ROOT/DEBIAN/prerm" <<'EOF'
#!/bin/bash
systemctl --user stop internet-agent.service 2>/dev/null || true
systemctl --user disable internet-agent.service 2>/dev/null || true
exit 0
EOF
chmod 0755 "$DEB_ROOT/DEBIAN/prerm"

mkdir -p "$OUT_DIR"
dpkg-deb --build --root-owner-group "$DEB_ROOT" \
  "$OUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"

rm -rf "$STAGE"
echo "Tayyor: $OUT_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
