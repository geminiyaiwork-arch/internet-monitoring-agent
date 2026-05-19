import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/platform/device_identity.dart';
import '../../../core/secure/secure_vault.dart';
import 'models/login_models.dart';

class AuthRepository {
  AuthRepository({
    required ApiClient api,
    required SecureVault vault,
    required AppDatabase db,
    required DeviceIdentityService identity,
    required AppLogger logger,
  })  : _api = api,
        _vault = vault,
        _db = db,
        _identity = identity,
        _logger = logger;

  final ApiClient _api;
  final SecureVault _vault;
  final AppDatabase _db;
  final DeviceIdentityService _identity;
  final AppLogger _logger;

  Future<bool> isLoggedIn() async {
    final st = await _vault.readLoginStatus();
    final key = await _vault.readAgentKey();
    return st == 'ok' && key != null && key.isNotEmpty;
  }

  /// Foydalanuvchi installer/login ekranida kiritgan key bilan login qiladi.
  /// Server javobida yangi `key` qaytarsa — saqlanadi (key rotation).
  Future<ApiEnvelope> loginWithKey(String agentKey, {String? userIdOpt}) async {
    _api.syncBaseUrl();
    final pkg = await PackageInfo.fromPlatform();
    final fingerprint = await _identity.machineGuidOrFingerprint();
    final req = LoginRequest(
      userId: userIdOpt == null ? null : int.tryParse(userIdOpt),
      deviceUid: fingerprint,
      deviceName: Platform.localHostname,
      machineGuid: fingerprint,
      appVersion: pkg.version,
      osVersion: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    try {
      final env = await _api.postJson(
        AppConfig.loginPath,
        req.toJson(),
        overrideKey: agentKey,
      );
      if (env.success) {
        // Server yangi key bersa o'shani, bo'lmasa kiritilgan keyni saqlaymiz.
        final finalKey = (env.key != null && env.key!.isNotEmpty)
            ? env.key!
            : agentKey;
        await _vault.writeAgentKey(finalKey);
        await _vault.setLoginStatus('ok');
        if (userIdOpt != null) await _vault.writeUserId(userIdOpt);
        await _db.updateAuthSession(
          lastLoginAt: DateTime.now().toUtc().toIso8601String(),
        );
        await _logger.log(LogLevel.info, 'Login muvaffaqiyatli');
      } else {
        await _logger.log(LogLevel.warn, 'Login rad etildi: ${env.message}');
      }
      return env;
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Login xatosi',
          error: e, stack: st);
      return ApiEnvelope(success: false, message: e.toString());
    }
  }

  Future<void> logoutLocal() async {
    await _vault.clearSession();
    await _logger.log(LogLevel.info, 'Lokal logout');
  }

  Future<String?> agentKey() => _vault.readAgentKey();
}
