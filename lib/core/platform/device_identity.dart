import 'dart:io';

import '../secure/secure_vault.dart';

/// Qurilmaning barqaror identifikatori — har platforma o'z manbasi bilan,
/// bo'lmasa secure storage'dagi UUID fallback.
class DeviceIdentityService {
  DeviceIdentityService(this._vault);

  final SecureVault _vault;

  Future<String> machineGuidOrFingerprint() async {
    try {
      if (Platform.isWindows) {
        final id = _windowsMachineGuid();
        if (id != null && id.isNotEmpty) {
          await _vault.setDeviceFingerprint(id);
          return id;
        }
      } else if (Platform.isMacOS) {
        final id = _macIoPlatformUuid();
        if (id != null && id.isNotEmpty) {
          await _vault.setDeviceFingerprint(id);
          return id;
        }
      } else if (Platform.isLinux) {
        final id = _linuxMachineId();
        if (id != null && id.isNotEmpty) {
          await _vault.setDeviceFingerprint(id);
          return id;
        }
      }
    } catch (_) {}
    return _vault.getOrCreateDeviceFingerprint();
  }

  /// Windows: HKLM\SOFTWARE\Microsoft\Cryptography MachineGuid.
  /// Bu yerda CLI orqali, win32_registry'ga qattiq bog'lanmaslik uchun.
  String? _windowsMachineGuid() {
    try {
      final res = Process.runSync(
        'reg',
        [
          'query',
          r'HKLM\SOFTWARE\Microsoft\Cryptography',
          '/v',
          'MachineGuid',
        ],
      );
      final out = res.stdout.toString();
      final m = RegExp(r'MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]+)')
          .firstMatch(out);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// macOS: IOPlatformUUID.
  String? _macIoPlatformUuid() {
    try {
      final res = Process.runSync(
        'ioreg',
        ['-d2', '-c', 'IOPlatformExpertDevice'],
      );
      final out = res.stdout.toString();
      final m = RegExp(r'"IOPlatformUUID"\s+=\s+"([^"]+)"').firstMatch(out);
      return m?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Linux: /etc/machine-id (yoki /var/lib/dbus/machine-id).
  String? _linuxMachineId() {
    for (final path in const [
      '/etc/machine-id',
      '/var/lib/dbus/machine-id',
    ]) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          final id = f.readAsStringSync().trim();
          if (id.isNotEmpty) return id;
        }
      } catch (_) {}
    }
    return null;
  }
}
