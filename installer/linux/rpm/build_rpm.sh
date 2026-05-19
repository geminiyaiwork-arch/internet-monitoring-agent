#!/usr/bin/env bash
# Internet Monitoring Agent — .rpm builder (Fedora/RHEL).
#
# Foydalanish:
#   sudo dnf install -y rpm-build gtk3-devel libsecret-devel \
#                       libayatana-appindicator3-devel ninja-build
#   flutter build linux --release
#   bash installer/linux/rpm/build_rpm.sh
#
# Natija: build/installer/internet-monitoring-agent-<v>-1.x86_64.rpm

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BUILD_OUT="$ROOT/build/linux/x64/release/bundle"
VERSION="$(grep '^version:' "$ROOT/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)"
OUT_DIR="$ROOT/build/installer"

if [ ! -d "$BUILD_OUT" ]; then
  echo "Xato: $BUILD_OUT topilmadi. 'flutter build linux --release' ishlatilsin." >&2
  exit 1
fi

TOP="$(mktemp -d)"
mkdir -p "$TOP/BUILD" "$TOP/RPMS" "$TOP/SOURCES" "$TOP/SPECS" "$TOP/SRPMS"

cp -r "$BUILD_OUT" "$TOP/SOURCES/bundle"
cp "$ROOT/installer/linux/systemd/internet-agent.service" "$TOP/SOURCES/"
[ -f "$ROOT/assets/branding/app_logo.png" ] && \
  cp "$ROOT/assets/branding/app_logo.png" "$TOP/SOURCES/app_logo.png"

cp "$ROOT/installer/linux/rpm/internet-agent.spec" "$TOP/SPECS/"

rpmbuild --define "_topdir $TOP" \
         --define "_version $VERSION" \
         -bb "$TOP/SPECS/internet-agent.spec"

mkdir -p "$OUT_DIR"
find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$OUT_DIR/" \;
rm -rf "$TOP"

echo "Tayyor: $OUT_DIR/ ostidagi .rpm fayllar"
ls -1 "$OUT_DIR"/*.rpm
