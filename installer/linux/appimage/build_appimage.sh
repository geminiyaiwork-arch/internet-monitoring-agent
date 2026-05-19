#!/usr/bin/env bash
# Internet Monitoring Agent — AppImage builder (portable, har qaysi distroda ishlaydi).
#
# Foydalanish:
#   flutter build linux --release
#   bash installer/linux/appimage/build_appimage.sh
#
# Natija: build/installer/InternetMonitoringAgent-<version>-x86_64.AppImage
#
# Talab: appimagetool (https://github.com/AppImage/AppImageKit/releases)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD_OUT="$ROOT/build/linux/x64/release/bundle"
VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)"
OUT_DIR="$ROOT/build/installer"
APPDIR="$(mktemp -d)/InternetMonitoringAgent.AppDir"

if [ ! -d "$BUILD_OUT" ]; then
  echo "Xato: $BUILD_OUT topilmadi. 'flutter build linux --release' ishlatilsin." >&2
  exit 1
fi

mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/applications" \
         "$APPDIR/usr/share/icons/hicolor/256x256/apps"

cp -r "$BUILD_OUT"/* "$APPDIR/usr/bin/"

# Desktop fayl
cat > "$APPDIR/usr/share/applications/internet-monitoring-agent.desktop" <<EOF
[Desktop Entry]
Name=Internet Monitoring Agent
Exec=internet
Icon=internet-monitoring-agent
Type=Application
Categories=Network;Utility;
StartupWMClass=internet
EOF
cp "$APPDIR/usr/share/applications/internet-monitoring-agent.desktop" "$APPDIR/"

# Icon
if [ -f "$ROOT/assets/branding/app_logo.png" ]; then
  cp "$ROOT/assets/branding/app_logo.png" \
     "$APPDIR/usr/share/icons/hicolor/256x256/apps/internet-monitoring-agent.png"
  cp "$ROOT/assets/branding/app_logo.png" "$APPDIR/internet-monitoring-agent.png"
fi

# AppRun
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib:$LD_LIBRARY_PATH"
exec "$HERE/usr/bin/internet" "$@"
EOF
chmod +x "$APPDIR/AppRun"

mkdir -p "$OUT_DIR"
APPIMAGE_PATH="$OUT_DIR/InternetMonitoringAgent-${VERSION}-x86_64.AppImage"

if ! command -v appimagetool >/dev/null 2>&1; then
  echo "Xato: appimagetool topilmadi. Yuklab oling:" >&2
  echo "  wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" >&2
  echo "  chmod +x appimagetool-x86_64.AppImage && sudo mv appimagetool-x86_64.AppImage /usr/local/bin/appimagetool" >&2
  exit 1
fi

ARCH=x86_64 appimagetool "$APPDIR" "$APPIMAGE_PATH"
rm -rf "$(dirname "$APPDIR")"

echo "Tayyor: $APPIMAGE_PATH"
