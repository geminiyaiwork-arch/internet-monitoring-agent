# Internet Monitoring Agent

Ta'lim muassasalari uchun ruxsatli, shaffof monitoring agenti.
**3 platformada ishlaydi: Windows, macOS, Linux.**

Server: `https://e-mmtb.uz/api/v1`

## Nima yig'adi (xizmat ko'rsatadigan vazifalar)

- **Internet tezligi** (download/upload Mbps, latency) — server bergan fayl orqali
- **O'rnatilgan dasturlar ro'yxati** (qaysi o'quv dasturlari bor)
- **Process snapshot** — ishlayotgan dasturlar nomi, PID, CPU%, RAM
- **Heartbeat** — qurilma holati: RAM/CPU/disk, tarmoq, uptime
- **Logs** — agentning ichki hodisalari (audit uchun)
- **Server buyruqlari** — `sync_now`, `speed_test`, `logout` kabi

**Yig'ilmaydi**: brauzer tarixi, parollar, xabar mazmuni, sayt kontenti.
Inventory va process — foydalanuvchi roziligi bilan (Settings'da).

## Talablar

- Flutter SDK `>=3.4.3 <4.0.0`
- Windows / macOS / Linux desktop

## Birinchi ishga tushirish

Ilova ochilganda **agent kalitini kiriting** (`X-Agent-Key`). Bu kalitni admin panel yaratadi va siz oddiy matn ko'rinishida (yoki QR/email) berasiz. Login muvaffaqiyatli bo'lsa kalit `flutter_secure_storage`da saqlanadi:
- Windows: DPAPI
- macOS: Keychain
- Linux: libsecret (gnome-keyring)

## Run (lokal sinov)

```bash
flutter pub get
flutter run -d windows    # yoki -d macos / -d linux
```

CLI argument bilan kalitni avtomatik yozish (msi/pkg/deb postinst uchun):

```bash
internet --key=AGENT-XXXX-YYYY --startup-tray
```

---

## API endpointlar (server tomon spetsifikatsiyasi)

Base: `/api/v1`, header: `X-Agent-Key: <kalit>`

| Yo'l | Metod | Tavsif |
|---|---|---|
| `/agent/login` | POST | Birinchi marta key bilan registratsiya |
| `/agent/heartbeat` | POST | Har 5 daqiqada: RAM/CPU/disk/tarmoq |
| `/agent/inventory` | POST | Har sutkada: o'rnatilgan dasturlar (diff) |
| `/agent/processes` | POST | Har 5 daqiqada: ishlayotgan jarayonlar |
| `/agent/speed-test` | POST | Har 30 daqiqada: Mbps natija |
| `/agent/logs` | POST | Har 5 daqiqada: yangi loglar |
| `/agent/commands` | GET | Har daqiqada: serverdan kelgan buyruqlar |

Standart javob:
```json
{
  "success": true,
  "message": "OK",
  "data": {},
  "key": null,                          // server kalit aylantirsa shu yerda
  "server_time": "2026-04-23T10:10:02Z",
  "next_interval": 300,
  "errors": null
}
```

---

## Build qadamlar (3 platforma)

### Windows
```bash
flutter build windows --release
# Inno Setup .exe:
ISCC.exe windows\installer\internet_agent.iss
# Yoki MSIX:
dart run msix:create
```

### macOS
```bash
flutter build macos --release
bash installer/macos/build_dmg.sh   # DMG (drag-drop)
bash installer/macos/build_pkg.sh   # PKG (LaunchAgent bilan)
```

### Linux

Avval dev kutubxonalar:
```bash
# Debian/Ubuntu:
sudo apt install -y libgtk-3-dev libsecret-1-dev libjsoncpp-dev \
                    libayatana-appindicator3-dev ninja-build clang cmake

# Fedora/RHEL:
sudo dnf install -y gtk3-devel libsecret-devel libayatana-appindicator3-devel \
                    ninja-build clang cmake rpm-build
```

Build:
```bash
flutter build linux --release
```

Paketlar:
```bash
bash installer/linux/deb/build_deb.sh             # .deb (Debian/Ubuntu)
bash installer/linux/rpm/build_rpm.sh             # .rpm (Fedora/RHEL)
bash installer/linux/appimage/build_appimage.sh   # AppImage (portable)
bash installer/linux/build_tarball.sh             # .tar.gz (manual)
```

Hammasi `build/installer/` ostiga chiqadi.

---

## Loyiha tuzilmasi

```
lib/
├── core/
│   ├── config/        AppConfig (URL, intervallar)
│   ├── database/      SQLite (settings, logs, queue, speed_history)
│   ├── network/       ApiClient (X-Agent-Key header), ApiEnvelope
│   ├── platform/      Win/Mac/Linux abstraksiyalari
│   │   ├── metrics/   RAM/CPU/disk (per OS)
│   │   ├── system_metrics_collector.dart
│   │   ├── single_instance.dart  (Mutex / file lock)
│   │   ├── startup_manager.dart  (launch_at_startup)
│   │   ├── device_identity.dart  (MachineGuid / IOPlatformUUID / /etc/machine-id)
│   │   └── tray_service.dart     (system_tray)
│   ├── scheduler/     AgentScheduler (heartbeat 5m, speed 30m, ...)
│   ├── secure/        SecureVault (Keychain/DPAPI/libsecret)
│   └── logging/       AppLogger
└── features/
    ├── auth/          LoginPage (key kiritish), AuthRepository
    ├── heartbeat/     HeartbeatRepository
    ├── inventory/     InventoryScanner (3 platforma), InventoryRepository
    ├── processes/     ProcessScanner (3 platforma), ProcessesRepository
    ├── speed_test/    SpeedTestClient (server fayli orqali)
    ├── commands/      CommandsRepository (server buyruqlari)
    ├── logs/          LogsRepository
    ├── dashboard/     Dashboard (statistikalar)
    ├── settings/      Settings (rozilik, URL'lar, startup)
    ├── privacy/       Privacy info sahifasi
    └── shell/         Tablar va shell

installer/
├── macos/             build_dmg.sh, build_pkg.sh + LaunchAgent
├── linux/
│   ├── deb/           .deb builder
│   ├── rpm/           .rpm spec + builder
│   ├── appimage/      AppImage builder
│   ├── systemd/       internet-agent.service
│   └── build_tarball.sh
└── (windows: windows/installer/internet_agent.iss)
```

---

## Privacy va xavfsizlik

- **Kalit** har doim secure storage'da (DPAPI / Keychain / libsecret), DB'da emas.
- **Diff inventory**: faqat o'zgargan dasturlar serverga yuboriladi (kamroq trafik).
- **Rozilik flag** Settings'da: inventory va processes alohida-alohida yoqiladi.
- **Server tomondan key rotation**: javobdagi `"key"` maydoni qiymat bersa, agent uni avtomatik almashtiradi va yangi key bilan davom etadi.
- **Key revoke**: server `revoked: true` qaytarsa, agent o'zini login ekraniga qaytaradi.
- **Single instance**: Windows — Named Mutex; macOS/Linux — fayl lock.
- **Tray**: barcha platforma'larda; Linux'da DE bo'lmasa UI rejimida davom etadi.

## Logs ko'rish

Tray menyu → **View Logs** yoki Settings sahifasidan. Loglar 30 kun saqlanadi (yo'q joyda) va `/agent/logs` orqali serverga yuboriladi.

## Test

```bash
flutter analyze   # static tahlil
flutter test       # widget testlar (sqflite_ffi va tray init bo'lmagani uchun cheklangan)
```
