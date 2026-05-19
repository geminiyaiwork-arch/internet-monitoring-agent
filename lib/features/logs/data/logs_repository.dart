import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/platform/device_identity.dart';
import '../../../core/secure/secure_vault.dart';

class LogsRepository {
  LogsRepository({
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

  Future<ApiEnvelope> ship({int batchSize = 200}) async {
    final key = await _vault.readAgentKey();
    if (key == null || key.isEmpty) {
      return ApiEnvelope(success: false, message: 'Not authenticated');
    }
    final rows = await _db.unsentLogs(limit: batchSize);
    if (rows.isEmpty) {
      return ApiEnvelope(success: true, message: 'No logs to ship');
    }
    final fp = await _identity.machineGuidOrFingerprint();
    final body = {
      'device_uid': fp,
      'logs': rows
          .map((r) => {
                'level': r['level'],
                'message': r['message'],
                'context': r['context'],
                'created_at': r['created_at'],
              })
          .toList(),
      'reported_at': DateTime.now().toUtc().toIso8601String(),
    };
    _api.syncBaseUrl();
    try {
      final env = await _api.postJson(AppConfig.logsPath, body);
      if (env.success) {
        final ids = rows.map((r) => r['id'] as int).toList();
        await _db.deleteLogsByIds(ids);
        await _logger.log(LogLevel.info, 'Logs yuborildi (${ids.length} ta)');
      } else {
        await _logger.log(LogLevel.warn, 'Logs rad: ${env.message}');
      }
      return env;
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Logs yuborishda xato',
          error: e, stack: st);
      return ApiEnvelope(success: false, message: e.toString());
    }
  }
}
