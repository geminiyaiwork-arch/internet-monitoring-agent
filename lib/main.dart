import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import 'app/internet_agent_app.dart';
import 'core/config/app_config.dart';
import 'core/database/app_database.dart';
import 'core/logging/app_logger.dart';
import 'core/network/api_client.dart';
import 'core/platform/device_identity.dart';
import 'core/platform/single_instance.dart';
import 'core/platform/system_metrics_collector.dart';
import 'core/scheduler/agent_scheduler.dart';
import 'core/secure/secure_vault.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/commands/data/commands_repository.dart';
import 'features/heartbeat/data/heartbeat_repository.dart';
import 'features/inventory/data/inventory_repository.dart';
import 'features/logs/data/logs_repository.dart';
import 'features/processes/data/processes_repository.dart';
import 'features/speed_test/data/speed_test_repository.dart';
import 'shared/providers/providers.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final startHidden = args.contains('--startup-tray');

  // sqflite FFI har uch desktop platformada ishlatiladi.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  if (!await acquireSingleInstanceLock()) {
    exit(0);
  }

  // CLI argument: --key=XXX -> tezda secure vaultga yozish (msi/pkg/installer uchun)
  await _maybeApplyKeyFromArgs(args);

  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  const windowOptions = WindowOptions(
    size: Size(1024, 680),
    center: true,
    title: AppConfig.appName,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (!startHidden) {
      await windowManager.show();
      await windowManager.focus();
    } else {
      await windowManager.hide();
    }
  });

  final db = await AppDatabase.open();
  await hydrateAppConfigFromDb(db);

  final vault = SecureVault();
  final api = ApiClient(vault);
  final metrics = SystemMetricsCollector();
  final identity = DeviceIdentityService(vault);
  final logger = AppLogger(db);

  final authRepo = AuthRepository(
    api: api,
    vault: vault,
    db: db,
    identity: identity,
    logger: logger,
  );
  final heartbeatRepo = HeartbeatRepository(
    api: api,
    vault: vault,
    db: db,
    metrics: metrics,
    identity: identity,
    logger: logger,
  );
  final inventoryRepo = InventoryRepository(
    api: api,
    vault: vault,
    db: db,
    identity: identity,
    logger: logger,
  );
  final processesRepo = ProcessesRepository(
    api: api,
    vault: vault,
    db: db,
    identity: identity,
    logger: logger,
  );
  final speedTestRepo = SpeedTestRepository(
    api: api,
    vault: vault,
    db: db,
    identity: identity,
    logger: logger,
  );
  final commandsRepo = CommandsRepository(
    api: api,
    vault: vault,
    db: db,
    logger: logger,
  );
  final logsRepo = LogsRepository(
    api: api,
    vault: vault,
    db: db,
    identity: identity,
    logger: logger,
  );
  final scheduler = AgentScheduler(
    db: db,
    auth: authRepo,
    heartbeat: heartbeatRepo,
    inventory: inventoryRepo,
    processes: processesRepo,
    speedTest: speedTestRepo,
    commands: commandsRepo,
    logs: logsRepo,
    logger: logger,
  );

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(api),
        agentSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: InternetAgentApp(startHidden: startHidden),
    ),
  );
}

Future<void> _maybeApplyKeyFromArgs(List<String> args) async {
  for (final a in args) {
    if (a.startsWith('--key=')) {
      final key = a.substring('--key='.length).trim();
      if (key.isNotEmpty) {
        await SecureVault().writeAgentKey(key);
        await SecureVault().setLoginStatus('ok');
      }
    }
  }
}
