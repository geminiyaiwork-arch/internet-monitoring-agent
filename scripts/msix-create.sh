#!/usr/bin/env sh
# Windowsda: avval `flutter build windows --release`, keyin shu skript yoki `dart run msix:create`.
# Linux/macOSda MSIX yaratib bo'lmaydi — GitHub Actions yoki Windows PC ishlating.

set -e
os=$(uname -s 2>/dev/null || printf unknown)
case "$os" in
  Linux|Darwin)
    printf "\n*** Bu OS (%s) da Windows .exe / MSIX yigilmaydi. ***\n" "$os"
    printf "    Flutter: \"build windows\" only supported on Windows hosts.\n"
    printf "\n    Nima qilish kerak:\n"
    printf "      • Windows kompyuterda: flutter build windows --release && dart run msix:create\n"
    printf "      • Yoki GitHub: Actions → Windows MSIX → Artifacts\n\n"
    exit 1
    ;;
esac

exec dart run msix:create "$@"
