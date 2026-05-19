import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/platform/device_identity.dart';
import '../../../core/secure/secure_vault.dart';
import 'process_scanner.dart';

class ProcessesRepository {
  ProcessesRepository({
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

  Future<ApiEnvelope> sync({bool manual = false}) async {
    final consent = await _db.getSetting('consent_processes') == 'true';
    if (!consent) {
      await _logger.log(LogLevel.info,
          'Processes: rozilik yo\'q, o\'tkazib yuborildi');
      return ApiEnvelope(success: false, message: 'No consent');
    }
    final key = await _vault.readAgentKey();
    if (key == null || key.isEmpty) {
      return ApiEnvelope(success: false, message: 'Not authenticated');
    }
    final scanner = createProcessScanner();
    final list = await scanner.scan();
    final fp = await _identity.machineGuidOrFingerprint();
    _api.syncBaseUrl();
    final body = <String, dynamic>{
      'device_uid': fp,
      'total': list.length,
      'reported_at': DateTime.now().toUtc().toIso8601String(),
      'processes': list.map((p) => p.toJson()).toList(),
    };
    try {
      final env = await _api.postJson(AppConfig.processesPath, body);
      if (env.success) {
        await _db.updateAuthSession(
            processesLastSentAt: DateTime.now().toUtc().toIso8601String());
        await _logger.log(
            LogLevel.info, 'Processes yuborildi (${list.length} ta)');
      } else {
        await _logger.log(LogLevel.warn, 'Processes rad: ${env.message}');
      }
      return env;
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Processes yuborishda xato',
          error: e, stack: st);
      return ApiEnvelope(success: false, message: e.toString());
    }
  }
}
