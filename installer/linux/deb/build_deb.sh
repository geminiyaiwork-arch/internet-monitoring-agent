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

cp -r "$BUILD_OUT"/* "$DEB_ROOT/opt/internet-monitoring-agent/"
cp "$ROOT/installer/linux/systemd/internet-agent.service" \
   "$DEB_ROOT/usr/lib/systemd/user/internet-agent.service"

# .desktop fayl
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
Depends: libgtk-3-0, libsecret-1-0, libayatana-appindicator3-1
Maintainer: E-MMTB <admin@e-mmtb.uz>
Description: Internet Monitoring Agent
 Authorized education monitoring agent for Linux desktops.
 Collects heartbeat, internet speed, installed apps and process
 snapshot for the central admin panel.
EOF

# postinst — agentni user-mode systemd'ga yozish
cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
chmod +x /opt/internet-monitoring-agent/internet || true
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
