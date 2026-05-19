#!/usr/bin/env bash
# Internet Monitoring Agent — oddiy tar.gz paket (manual o'rnatish).
#
#   flutter build linux --release
#   bash installer/linux/build_tarball.sh
#
# Natija: build/installer/internet-monitoring-agent-<version>-linux-x64.tar.gz
#
# O'rnatish (root):
#   sudo tar -C / -xzf internet-monitoring-agent-*.tar.gz
#   systemctl --user daemon-reload
#   systemctl --user enable --now internet-agent.service

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_OUT="$ROOT/build/linux/x64/release/bundle"
VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)"
OUT_DIR="$ROOT/build/installer"
STAGE="$(mktemp -d)"

if [ ! -d "$BUILD_OUT" ]; then
  echo "Xato: $BUILD_OUT topilmadi. 'flutter build linux --release' ishlatilsin." >&2
  exit 1
fi

mkdir -p "$STAGE/opt/internet-monitoring-agent"
mkdir -p "$STAGE/usr/share/applications"
mkdir -p "$STAGE/usr/lib/systemd/user"

cp -r "$BUILD_OUT"/* "$STAGE/opt/internet-monitoring-agent/"
cp "$ROOT/installer/linux/systemd/internet-agent.service" \
   "$STAGE/usr/lib/systemd/user/internet-agent.service"

cat > "$STAGE/usr/share/applications/internet-monitoring-agent.desktop" <<EOF
[Desktop Entry]
Name=Internet Monitoring Agent
Exec=/opt/internet-monitoring-agent/internet
Icon=internet-monitoring-agent
Type=Application
Categories=Network;Utility;
EOF

mkdir -p "$OUT_DIR"
TAR="$OUT_DIR/internet-monitoring-agent-${VERSION}-linux-x64.tar.gz"
tar -C "$STAGE" -czf "$TAR" opt usr
rm -rf "$STAGE"

echo "Tayyor: $TAR"
