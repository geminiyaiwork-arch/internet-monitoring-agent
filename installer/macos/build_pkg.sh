#!/usr/bin/env bash
# Internet Monitoring Agent — macOS PKG installer + LaunchAgent.
#
# Foydalanish (macOS hostda):
#   flutter build macos --release
#   bash installer/macos/build_pkg.sh
#
# Natija: build/installer/InternetMonitoringAgent-<version>.pkg
#
# Bu installer .app ni /Applications/ ga ko'chiradi va
# ~/Library/LaunchAgents/uz.emmtb.internetmonitoringagent.plist
# faylini o'rnatib agentni login paytida ishga tushiradi.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APP_BUNDLE="$ROOT/build/macos/Build/Products/Release/internet.app"
OUT_DIR="$ROOT/build/installer"
VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)"
PKG_ID="uz.emmtb.internetmonitoringagent"
PKG_NAME="InternetMonitoringAgent-${VERSION}.pkg"
STAGE="$(mktemp -d)"
SCRIPTS="$(mktemp -d)"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "Xato: $APP_BUNDLE topilmadi. 'flutter build macos --release' ishlatilsin." >&2
  exit 1
fi

mkdir -p "$STAGE/Applications"
cp -R "$APP_BUNDLE" "$STAGE/Applications/Internet Monitoring Agent.app"
codesign --force --deep --sign - "$STAGE/Applications/Internet Monitoring Agent.app" || true

# postinstall: LaunchAgent o'rnatish
cat > "$SCRIPTS/postinstall" <<'POSTEOF'
#!/bin/bash
USER_HOME=$(eval echo "~$USER")
PLIST="$USER_HOME/Library/LaunchAgents/uz.emmtb.internetmonitoringagent.plist"
mkdir -p "$USER_HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>uz.emmtb.internetmonitoringagent</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Applications/Internet Monitoring Agent.app/Contents/MacOS/internet</string>
    <string>--startup-tray</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict>
</plist>
EOF
launchctl load -w "$PLIST" 2>/dev/null || true
exit 0
POSTEOF
chmod +x "$SCRIPTS/postinstall"

mkdir -p "$OUT_DIR"
pkgbuild \
  --root "$STAGE" \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --install-location "/" \
  --scripts "$SCRIPTS" \
  "$OUT_DIR/$PKG_NAME"

rm -rf "$STAGE" "$SCRIPTS"
echo "Tayyor: $OUT_DIR/$PKG_NAME"
