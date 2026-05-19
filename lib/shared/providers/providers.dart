import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/database/app_database.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_client.dart';
import '../../core/platform/device_identity.dart';
import '../../core/platform/startup_manager.dart';
import '../../core/platform/system_metrics_collector.dart';
import '../../core/platform/tray_service.dart';
import '../../core/scheduler/agent_scheduler.dart';
import '../../core/secure/secure_vault.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/commands/data/commands_repository.dart';
import '../../features/heartbeat/data/heartbeat_repository.dart';
import '../../features/inventory/data/inventory_repository.dart';
import '../../features/logs/data/logs_repository.dart';
import '../../features/processes/data/processes_repository.dart';
import '../../features/speed_test/data/speed_test_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider must be overridden in main()');
});

final secureVaultProvider = Provider<SecureVault>((ref) => SecureVault());

final appLoggerProvider = Provider<AppLogger>((ref) {
  return AppLogger(ref.watch(appDatabaseProvider));
});

final apiClientProvider = Provider<ApiClient>((ref) {
  throw UnimplementedError('apiClientProvider must be overridden in main()');
});

final deviceIdentityProvider = Provider<DeviceIdentityService>((ref) {
  return DeviceIdentityService(ref.watch(secureVaultProvider));
});

final systemMetricsProvider = Provider<SystemMetricsCollector>((ref) {
  return SystemMetricsCollector();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(apiClientProvider),
    vault: ref.watch(secureVaultProvider),
    db: ref.watch(appDatabaseProvider),
    identity: ref.watch(deviceIdentityProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final heartbeatRepositoryProvider = Provider<HeartbeatRepository>((ref) {
  return HeartbeatRepository(
    api: ref.watch(apiClientProvider),
    vault: ref.watch(secureVaultProvider),
    db: ref.watch(appDatabaseProvider),
    metrics: ref.watch(systemMetricsProvider),
    identity: ref.watch(deviceIdentityProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(
    api: ref.watch(apiClientProvider),
    vault: ref.watch(secureVaultProvider),
    db: ref.watch(appDatabaseProvider),
    identity: ref.watch(deviceIdentityProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final processesRepositoryProvider = Provider<ProcessesRepository>((ref) {
  return ProcessesRepository(
    api: ref.watch(apiClientProvider),
    vault: ref.watch(secureVaultProvider),
    db: ref.watch(appDatabaseProvider),
    identity: ref.watch(deviceIdentityProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final speedTestRepositoryProvider = Provider<SpeedTestRepository>((ref) {
  return SpeedTestRepository(
    api: ref.watch(apiClientProvider),
    vault: ref.watch(secureVaultProvider),
    db: ref.watch(appDatabaseProvider),
    identity: ref.watch(deviceIdentityProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final commandsRepositoryProvider = Provider<CommandsRepository>((ref) {
  return CommandsRepository(
    api: ref.watch(apiClientProvider),
    vault: ref.watch(secureVaultProvider),
    db: ref.watch(appDatabaseProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final logsRepositoryProvider = Provider<LogsRepository>((ref) {
  return LogsRepository(
    api: ref.watch(apiClientProvider),
    vault: ref.watch(secureVaultProvider),
    db: ref.watch(appDatabaseProvider),
    identity: ref.watch(deviceIdentityProvider),
    logger: ref.watch(appLoggerProvider),
  );
});

final startupManagerProvider = Provider<StartupManager>((ref) {
  return DesktopStartupManager();
});

final agentSchedulerProvider = Provider<AgentScheduler>((ref) {
  throw UnimplementedError(
      'agentSchedulerProvider must be overridden in main()');
});

final trayServiceProvider = Provider<TrayService>((ref) => TrayService());

class AuthSessionNotifier extends StateNotifier<bool?> {
  AuthSessionNotifier(this._auth) : super(null) {
    refresh();
  }

  final AuthRepository _auth;

  Future<void> refresh() async {
    state = null;
    state = await _auth.isLoggedIn();
  }
}

final authSessionProvider =
    StateNotifierProvider<AuthSessionNotifier, bool?>((ref) {
  return AuthSessionNotifier(ref.watch(authRepositoryProvider));
});

/// SQLite settings -> AppConfig
Future<void> hydrateAppConfigFromDb(AppDatabase db) async {
  final bu = await db.getSetting('base_url');
  if (bu != null && bu.isNotEmpty) {
    AppConfig.instance.baseUrl = bu;
  }
  final mock = await db.getSetting('use_mock_api');
  if (mock != null) {
    AppConfig.instance.useMockApi = mock == 'true';
  }
}
