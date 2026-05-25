import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Maxfiy saqlash:
/// - Windows: DPAPI
/// - Linux:   libsecret (gnome-keyring)
class SecureVault {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    lOptions: LinuxOptions(),
    mOptions: MacOsOptions(),
    wOptions: WindowsOptions(),
  );

  static const _kAgentKey = 'agent_key';
  static const _kDeviceFingerprint = 'device_fingerprint';
  static const _kLoginStatus = 'login_status';
  static const _kLastUserId = 'last_user_id';

  Future<void> writeAgentKey(String key) =>
      _storage.write(key: _kAgentKey, value: key);

  Future<String?> readAgentKey() => _storage.read(key: _kAgentKey);

  Future<void> setLoginStatus(String status) =>
      _storage.write(key: _kLoginStatus, value: status);

  Future<String?> readLoginStatus() => _storage.read(key: _kLoginStatus);

  Future<void> writeUserId(String userId) =>
      _storage.write(key: _kLastUserId, value: userId);

  Future<String?> readUserId() => _storage.read(key: _kLastUserId);

  Future<void> clearSession() async {
    await _storage.delete(key: _kAgentKey);
    await _storage.delete(key: _kLoginStatus);
    await _storage.delete(key: _kLastUserId);
  }

  Future<String> getOrCreateDeviceFingerprint() async {
    final existing = await _storage.read(key: _kDeviceFingerprint);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await _storage.write(key: _kDeviceFingerprint, value: id);
    return id;
  }

  Future<void> setDeviceFingerprint(String value) =>
      _storage.write(key: _kDeviceFingerprint, value: value);
}
