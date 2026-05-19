import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/platform/device_identity.dart';
import '../../../core/secure/secure_vault.dart';
import 'speed_test_client.dart';

class SpeedTestRepository {
  SpeedTestRepository({
    required ApiClient api,
    required SecureVault vault,
    required AppDatabase db,
    required DeviceIdentityService identity,
    required AppLogger logger,
    SpeedTestClient? client,
  })  : _api = api,
        _vault = vault,
        _db = db,
        _identity = identity,
        _logger = logger,
        _client = client ?? SpeedTestClient();

  final ApiClient _api;
  final SecureVault _vault;
  final AppDatabase _db;
  final DeviceIdentityService _identity;
  final AppLogger _logger;
  final SpeedTestClient _client;

  /// Server endpointlari Settings yoki commands orqali kelishi mumkin.
  /// Default sifatida base_url + /speed-test/* yo'llaridan foydalanadi.
  Future<ApiEnvelope> runAndReport({bool manual = false}) async {
    final key = await _vault.readAgentKey();
    if (key == null || key.isEmpty) {
      return ApiEnvelope(success: false, message: 'Not authenticated');
    }
    final downloadUrl =
        await _db.getSetting('speedtest_download_url') ??
            '${AppConfig.instance.baseUrl}/speed-test/download';
    final uploadUrl = await _db.getSetting('speedtest_upload_url') ??
        '${AppConfig.instance.baseUrl}/speed-test/upload';
    final latencyUrl = await _db.getSetting('speedtest_latency_url') ??
        '${AppConfig.instance.baseUrl}/speed-test/ping';

    final result = await _client.run(
      downloadUrl: downloadUrl,
      uploadUrl: uploadUrl,
      latencyUrl: latencyUrl,
      downloadBytes: AppConfig.speedTestDefaultBytes,
    );

    await _db.insertSpeedHistory({
      'tested_at': result.testedAt.toUtc().toIso8601String(),
      'download_mbps': result.downloadMbps,
      'upload_mbps': result.uploadMbps,
      'latency_ms': result.latencyMs,
      'bytes_down': result.bytesDown,
      'bytes_up': result.bytesUp,
      'server': result.serverHost,
      'error': result.error,
    });

    final fp = await _identity.machineGuidOrFingerprint();
    _api.syncBaseUrl();
    final body = <String, dynamic>{
      'device_uid': fp,
      ...result.toJson(),
    };
    try {
      final env = await _api.postJson(AppConfig.speedTestPath, body);
      if (env.success) {
        await _db.updateAuthSession(
            speedtestLastSentAt: DateTime.now().toUtc().toIso8601String());
        await _logger.log(LogLevel.info,
            'Speed test: ↓${result.downloadMbps.toStringAsFixed(1)} Mbps ↑${result.uploadMbps.toStringAsFixed(1)} Mbps');
      } else {
        await _logger.log(LogLevel.warn, 'Speed test rad: ${env.message}');
      }
      return env;
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Speed test yuborishda xato',
          error: e, stack: st);
      return ApiEnvelope(success: false, message: e.toString());
    }
  }
}
