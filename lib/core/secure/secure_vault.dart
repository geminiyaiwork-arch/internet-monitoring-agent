import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Maxfiy saqlash:
/// - Windows: DPAPI (flutter_secure_storage)
/// - Linux:   plain file (gnome-keyring ishonchsiz Kali/headless'da)
///
/// Kalit oddiy faylda saqlanadi: ~/.config/internet-agent/vault.json
/// Fayl 0600 (faqat user o'qiy oladi). Ushbu app monitoring agent uchun mo'ljallangan,
/// va keyring xizmati har doim mavjud emas (server, kiosk, autostart).
class SecureVault {
  static const _kAgentKey = 'agent_key';
  static const _kDeviceFingerprint = 'device_fingerprint';
  static const _kLoginStatus = 'login_status';
  static const _kLastUserId = 'last_user_id';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    wOptions: WindowsOptions(),
  );

  Map<String, String>? _cache;
  File? _vaultFile;

  Future<File> _file() async {
    if (_vaultFile != null) return _vaultFile!;
    final dir = await getApplicationSupportDirectory();
    final root = Directory(p.join(dir.path, 'ima'));
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    final f = File(p.join(root.path, 'vault.json'));
    if (!f.existsSync()) {
      f.writeAsStringSync('{}');
      if (!Platform.isWindows) {
        try {
          Process.runSync('chmod', ['600', f.path]);
        } catch (_) {}
      }
    }
    _vaultFile = f;
    return f;
  }

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    final f = await _file();
    try {
      final raw = f.readAsStringSync();
      final m = <String, String>{};
      // Oddiy parser — har bir qator: key=value
      // Yoki JSON-like {"k":"v"}
      if (raw.trim().startsWith('{')) {
        final inner = raw.trim().substring(1, raw.trim().length - 1);
        for (final part in inner.split(',')) {
          final t = part.trim();
          if (t.isEmpty) continue;
          final colon = t.indexOf(':');
          if (colon < 0) continue;
          final k = t.substring(0, colon).trim().replaceAll('"', '');
          final v = t.substring(colon + 1).trim().replaceAll('"', '');
          if (k.isNotEmpty) m[k] = v;
        }
      }
      _cache = m;
      return m;
    } catch (_) {
      _cache = {};
      return _cache!;
    }
  }

  Future<void> _save() async {
    final f = await _file();
    final m = _cache ?? {};
    final entries = m.entries.map((e) => '"${e.key}":"${e.value.replaceAll('"', r'\"')}"').join(',');
    f.writeAsStringSync('{$entries}');
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', ['600', f.path]);
      } catch (_) {}
    }
  }

  Future<String?> _read(String key) async {
    if (Platform.isWindows) {
      try {
        return await _storage.read(key: key).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    final m = await _load();
    return m[key];
  }

  Future<void> _write(String key, String value) async {
    if (Platform.isWindows) {
      try {
        await _storage.write(key: key, value: value).timeout(const Duration(seconds: 3));
        return;
      } catch (_) {}
    }
    final m = await _load();
    m[key] = value;
    _cache = m;
    await _save();
  }

  Future<void> _delete(String key) async {
    if (Platform.isWindows) {
      try {
        await _storage.delete(key: key).timeout(const Duration(seconds: 3));
        return;
      } catch (_) {}
    }
    final m = await _load();
    m.remove(key);
    _cache = m;
    await _save();
  }

  Future<void> writeAgentKey(String key) => _write(_kAgentKey, key);
  Future<String?> readAgentKey() => _read(_kAgentKey);

  Future<void> setLoginStatus(String status) => _write(_kLoginStatus, status);
  Future<String?> readLoginStatus() => _read(_kLoginStatus);

  Future<void> writeUserId(String userId) => _write(_kLastUserId, userId);
  Future<String?> readUserId() => _read(_kLastUserId);

  Future<void> clearSession() async {
    await _delete(_kAgentKey);
    await _delete(_kLoginStatus);
    await _delete(_kLastUserId);
  }

  Future<String> getOrCreateDeviceFingerprint() async {
    final existing = await _read(_kDeviceFingerprint);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await _write(_kDeviceFingerprint, id);
    return id;
  }

  Future<void> setDeviceFingerprint(String value) => _write(_kDeviceFingerprint, value);
}
