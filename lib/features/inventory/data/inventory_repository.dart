import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/platform/device_identity.dart';
import '../../../core/secure/secure_vault.dart';
import 'inventory_scanner.dart';

class InventoryRepository {
  InventoryRepository({
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
    final consent = await _db.getSetting('consent_inventory') == 'true';
    if (!consent) {
      await _logger.log(LogLevel.info, 'Inventory: rozilik yo\'q, o\'tkazib yuborildi');
      return ApiEnvelope(success: false, message: 'No consent');
    }
    final key = await _vault.readAgentKey();
    if (key == null || key.isEmpty) {
      return ApiEnvelope(success: false, message: 'Not authenticated');
    }
    final session = await _db.getAuthSessionRow();
    final lastSentStr = session['inventory_last_sent_at'] as String?;
    if (!manual && lastSentStr != null) {
      final last = DateTime.tryParse(lastSentStr);
      if (last != null &&
          DateTime.now().toUtc().difference(last) <
              AppConfig.defaultInventoryInterval) {
        return ApiEnvelope(success: true, message: 'Skipped (daily window)');
      }
    }
    final scanner = createInventoryScanner();
    final current = await scanner.scan();
    final currentByHash = {for (final a in current) a.computeHash(): a};
    final cached = await _db.allInventoryCache();
    final cachedHashes = cached.map((r) => r['record_hash'] as String).toSet();
    final currentHashes = currentByHash.keys.toSet();
    final added = currentByHash.entries
        .where((e) => !cachedHashes.contains(e.key))
        .map((e) => e.value.toJson())
        .toList();
    final removed = cached
        .where((r) => !currentHashes.contains(r['record_hash'] as String))
        .map((r) => r['display_name']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    if (added.isEmpty && removed.isEmpty && lastSentStr != null) {
      await _db.updateAuthSession(
          inventoryLastUpdate: DateTime.now().toUtc().toIso8601String());
      return ApiEnvelope(success: true, message: 'No inventory changes');
    }
    _api.syncBaseUrl();
    final fp = await _identity.machineGuidOrFingerprint();
    // Server `collected_at`, `apps_count`, `items[]` kutadi (full snapshot).
    final body = <String, dynamic>{
      'device_uid': fp,
      'collected_at': DateTime.now().toUtc().toIso8601String(),
      'apps_count': current.length,
      'items': current.map((a) => {
        'display_name': a.displayName,
        if (a.displayVersion != null) 'display_version': a.displayVersion,
        if (a.publisher != null) 'publisher': a.publisher,
        if (a.installDate != null) 'install_date': a.installDate,
      }).toList(),
    };
    try {
      final env = await _api.postJson(AppConfig.inventoryPath, body);
      if (env.success) {
        await _db.clearInventoryCache();
        final rows = current
            .map((a) => <String, Object?>{
                  'display_name': a.displayName,
                  'display_version': a.displayVersion,
                  'publisher': a.publisher,
                  'install_date': a.installDate,
                  'record_hash': a.computeHash(),
                })
            .toList();
        if (rows.isNotEmpty) {
          await _db.upsertInventoryRows(rows);
        }
        final now = DateTime.now().toUtc().toIso8601String();
        await _db.updateAuthSession(
          inventoryLastSentAt: now,
          inventoryLastUpdate: now,
        );
        await _logger.log(LogLevel.info,
            'Inventory yuborildi (+${added.length} / -${removed.length})');
      } else {
        await _logger.log(LogLevel.warn, 'Inventory rad: ${env.message}');
      }
      return env;
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Inventory yuborishda xato',
          error: e, stack: st);
      return ApiEnvelope(success: false, message: e.toString());
    }
  }
}
