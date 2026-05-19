#!/usr/bin/env bash
# GitHub-ga yuklash skripti — bir martalik ishga tushirish.
# Username: geminiyaiwork-arch
# Repo:     internet-monitoring-agent

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GITHUB_USER="geminiyaiwork-arch"
GITHUB_EMAIL="geminiyaiwork@gmail.com"
REPO_NAME="internet-monitoring-agent"
REMOTE_URL="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

echo "==> Git identity sozlash"
git config user.name "${GITHUB_USER}"
git config user.email "${GITHUB_EMAIL}"

# Agar git init qilinmagan bo'lsa
if [ ! -d .git ]; then
  echo "==> git init"
  git init -b main
fi

# Remote bor-yo'qligini tekshirish
if git remote get-url origin >/dev/null 2>&1; then
  echo "==> 'origin' allaqachon bor: $(git remote get-url origin)"
  git remote set-url origin "$REMOTE_URL"
else
  echo "==> Remote qo'shish: $REMOTE_URL"
  git remote add origin "$REMOTE_URL"
fi

echo "==> Branch nomi: main"
git branch -M main 2>/dev/null || true

echo "==> Fayllarni stage qilish"
git add .

# Commit kerak bo'lsa
if git diff --cached --quiet; then
  echo "==> O'zgarish yo'q, commit o'tkazib yuborildi"
else
  echo "==> Commit"
  git commit -m "Initial: 3-platform monitoring agent (Windows/macOS/Linux)

- Foundation: AppConfig, SecureVault, ApiClient (X-Agent-Key)
- Platform abstraksiyalari: Win/Mac/Linux (metrics, identity, scanners)
- Repositorylar: auth, heartbeat, inventory, processes, speed-test, logs, commands
- Login UI: agent kalitini kiritish
- Installerlar: MSIX/Inno (Win), DMG/PKG (Mac), DEB/RPM/AppImage/tar.gz (Linux)
- GitHub Actions: 3 platformada avtomatik build + Releases + Pages"
fi

echo "==> Push (sizdan token so'raydi)"
echo "    Username: ${GITHUB_USER}"
echo "    Password: <GitHub Personal Access Token>"
echo "    Token: https://github.com/settings/tokens (scopes: repo, workflow)"
git push -u origin main

echo ""
echo "==> Tayyor! Endi:"
echo "    1. GitHub repo -> Settings -> Pages -> Source: 'GitHub Actions'"
echo "    2. Release chiqarish: git tag v1.0.0 && git push origin v1.0.0"
echo ""
echo "==> URLlar:"
echo "    Repo:      https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo "    Actions:   https://github.com/${GITHUB_USER}/${REPO_NAME}/actions"
echo "    Releases:  https://github.com/${GITHUB_USER}/${REPO_NAME}/releases"
echo "    Pages:     https://${GITHUB_USER}.github.io/${REPO_NAME}/"
