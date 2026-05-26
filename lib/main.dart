import 'dart:io';
import 'dart:ui';

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
import 'features/stream/data/stream_service.dart';
import 'shared/providers/providers.dart';

Future<void> main(List<String> args) async {
  // Release build'da console yo'q — har qanday xato faylga yozilsin.
  // %LOCALAPPDATA%\internet-monitoring-agent\startup.log (Win)
  // ~/.local/share/internet-monitoring-agent/startup.log (Linux)
  await _logStartup('=== main() boshlandi: ${DateTime.now().toIso8601String()} ===');
  await _logStartup('args=$args, platform=${Platform.operatingSystem}');

  // Top-level xatolarni ushlash.
  FlutterError.onError = (FlutterErrorDetails details) {
    _logStartup('FLUTTER_ERROR: ${details.exception}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _logStartup('PLATFORM_ERROR: $error\n$stack');
    return true;
  };

  try {
    WidgetsFlutterBinding.ensureInitialized();
    await _logStartup('1. WidgetsFlutterBinding OK');
  } catch (e, st) {
    await _logStartup('WidgetsFlutterBinding FAIL: $e\n$st');
    rethrow;
  }

  final startHidden = args.contains('--startup-tray');

  try {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _logStartup('2. sqflite FFI OK');
  } catch (e, st) {
    await _logStartup('sqflite FFI FAIL: $e\n$st');
    rethrow;
  }

  try {
    if (!await acquireSingleInstanceLock()) {
      await _logStartup('3. Single-instance lock — boshqa instance bor, exit.');
      exit(0);
    }
    await _logStartup('3. Single-instance lock OK');
  } catch (e, st) {
    await _logStartup('Single-instance FAIL: $e\n$st');
  }

  try {
    await _maybeApplyKeyFromArgs(args);
    await _logStartup('4. CLI key apply OK');
  } catch (e, st) {
    await _logStartup('CLI key apply FAIL: $e\n$st');
  }

  try {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    const windowOptions = WindowOptions(
      size: Size(1024, 680),
      center: true,
      title: AppConfig.appName,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      try {
        if (!startHidden) {
          await windowManager.show();
          await windowManager.focus();
          await _logStartup('5b. window show+focus OK');
        } else {
          await windowManager.hide();
          await _logStartup('5b. window hide OK');
        }
      } catch (e, st) {
        await _logStartup('window show/hide FAIL: $e\n$st');
      }
    });
    await _logStartup('5a. windowManager init OK');
  } catch (e, st) {
    await _logStartup('windowManager FAIL: $e\n$st');
    rethrow;
  }

  final AppDatabase db;
  try {
    db = await AppDatabase.open();
    await _logStartup('6. AppDatabase OK');
  } catch (e, st) {
    await _logStartup('AppDatabase FAIL: $e\n$st');
    rethrow;
  }
  try {
    await hydrateAppConfigFromDb(db);
    await _logStartup('7. AppConfig hydrate OK');
  } catch (e, st) {
    await _logStartup('AppConfig hydrate FAIL: $e\n$st');
  }

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
  final streamService = StreamService(api: api, vault: vault, logger: logger);
  // Notifier singleton — scheduler callback'lari va UI shu instance bilan ishlaydi.
  final streamUi = StreamUiNotifier();

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
    stream: streamService,
    onStreamStart: (sid, admin) =>
        streamUi.start(sessionId: sid, adminName: admin),
    onStreamStop: () => streamUi.stop(),
  );

  await _logStartup('8. Repositories OK, runApp boshlanmoqda...');
  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(api),
        secureVaultProvider.overrideWithValue(vault),
        streamServiceProvider.overrideWithValue(streamService),
        streamUiProvider.overrideWith((ref) => streamUi),
        agentSchedulerProvider.overrideWithValue(scheduler),
      ],
      child: InternetAgentApp(startHidden: startHidden),
    ),
  );
  await _logStartup('9. runApp chaqirildi (UI yuklanmoqda)');
}

Future<void> _logStartup(String line) async {
  try {
    String path;
    if (Platform.isWindows) {
      final appData = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['TEMP'] ?? '.';
      final dir = Directory('$appData\\internet-monitoring-agent');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      path = '${dir.path}\\startup.log';
    } else {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final dir = Directory('$home/.local/share/internet-monitoring-agent');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      path = '${dir.path}/startup.log';
    }
    final f = File(path);
    final ts = DateTime.now().toIso8601String();
    f.writeAsStringSync('[$ts] $line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
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
