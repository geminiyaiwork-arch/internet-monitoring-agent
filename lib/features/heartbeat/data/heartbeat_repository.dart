import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/platform/device_identity.dart';
import '../../../core/platform/system_metrics_collector.dart';
import '../../../core/secure/secure_vault.dart';
import 'models/heartbeat_models.dart';

class HeartbeatRepository {
  HeartbeatRepository({
    required ApiClient api,
    required SecureVault vault,
    required AppDatabase db,
    required SystemMetricsCollector metrics,
    required DeviceIdentityService identity,
    required AppLogger logger,
  })  : _api = api,
        _vault = vault,
        _db = db,
        _metrics = metrics,
        _identity = identity,
        _logger = logger;

  final ApiClient _api;
  final SecureVault _vault;
  final AppDatabase _db;
  final SystemMetricsCollector _metrics;
  final DeviceIdentityService _identity;
  final AppLogger _logger;

  Future<HeartbeatRequest?> _buildRequest({String? deviceNameOverride}) async {
    final key = await _vault.readAgentKey();
    if (key == null || key.isEmpty) return null;
    _api.syncBaseUrl();
    final pkg = await PackageInfo.fromPlatform();
    final net = await _metrics.networkStatusLabel();
    final localIp = await _metrics.primaryLocalIp();
    String? pubIp;
    if (net == 'online') {
      pubIp = await _metrics.fetchPublicIp();
    }
    final snap = _metrics.readResources();
    final fp = await _identity.machineGuidOrFingerprint();
    return HeartbeatRequest(
      deviceUid: fp,
      deviceName: deviceNameOverride ?? Platform.localHostname,
      computerUsername: Platform.environment['USERNAME'] ??
          Platform.environment['USER'] ??
          'unknown',
      osName: Platform.operatingSystem,
      osVersion: Platform.operatingSystemVersion,
      appVersion: pkg.version,
      localIp: localIp,
      publicIp: pubIp,
      networkStatus: net,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      uptime: _metrics.uptimeSeconds(),
      ramTotalMb: snap.ramTotalMb,
      ramUsedMb: snap.ramUsedMb,
      diskTotalMb: snap.diskTotalMb,
      diskFreeMb: snap.diskFreeMb,
      cpuUsage: snap.cpuUsagePercent,
    );
  }

  Future<ApiEnvelope> sendHeartbeat({String? deviceNameOverride}) async {
    final hb = await _buildRequest(deviceNameOverride: deviceNameOverride);
    if (hb == null) {
      return ApiEnvelope(success: false, message: 'Not authenticated');
    }
    try {
      final env = await _api.postJson(AppConfig.heartbeatPath, hb.toJson());
      await _applyEnvelope(env);
      return env;
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Heartbeat transport xatosi',
          error: e, stack: st);
      rethrow;
    }
  }

  Future<void> _applyEnvelope(ApiEnvelope env) async {
    if (env.sessionRevoked) {
      await _logger.log(LogLevel.warn, 'Server kalitni bekor qildi');
      await _vault.clearSession();
      return;
    }
    if (env.success) {
      await _db.updateAuthSession(
          lastSuccessSync: DateTime.now().toUtc().toIso8601String());
      if (env.key != null && env.key!.isNotEmpty) {
        await _vault.writeAgentKey(env.key!);
      }
      if (env.nextIntervalSec != null && env.nextIntervalSec! >= 30) {
        await _db.setSetting(
            'heartbeat_interval_sec', env.nextIntervalSec!.toString());
      }
      await _logger.log(LogLevel.info, 'Heartbeat OK');
    } else {
      await _logger.log(LogLevel.warn, 'Heartbeat rad: ${env.message}');
    }
  }

  Future<Map<String, dynamic>?> buildHeartbeatJson(
      {String? deviceNameOverride}) async {
    final r = await _buildRequest(deviceNameOverride: deviceNameOverride);
    return r?.toJson();
  }

  Future<ApiEnvelope> postHeartbeatJson(Map<String, dynamic> body) async {
    _api.syncBaseUrl();
    final env = await _api.postJson(AppConfig.heartbeatPath, body);
    await _applyEnvelope(env);
    return env;
  }
}
