#!/usr/bin/env bash
# Internet Monitoring Agent — macOS DMG builder.
#
# Foydalanish (macOS hostda):
#   flutter build macos --release
#   bash installer/macos/build_dmg.sh
#
# Natija: build/installer/InternetMonitoringAgent-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_NAME="Internet Monitoring Agent"
APP_BUNDLE="$ROOT/build/macos/Build/Products/Release/internet.app"
OUT_DIR="$ROOT/build/installer"
VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)"
DMG_NAME="InternetMonitoringAgent-${VERSION}.dmg"
STAGING="$(mktemp -d)"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Xato: $APP_BUNDLE topilmadi. Avval 'flutter build macos --release' ishlatilsin." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cp -R "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# Codesign (ad-hoc, agar sertifikat bo'lmasa)
codesign --force --deep --sign - "$STAGING/$APP_NAME.app" || true

hdiutil create -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$OUT_DIR/$DMG_NAME"

rm -rf "$STAGING"
echo "Tayyor: $OUT_DIR/$DMG_NAME"
