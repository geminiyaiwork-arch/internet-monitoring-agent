import 'dart:async';
import 'dart:convert';

import '../../features/auth/data/auth_repository.dart';
import '../../features/commands/data/commands_repository.dart';
import '../../features/heartbeat/data/heartbeat_repository.dart';
import '../../features/inventory/data/inventory_repository.dart';
import '../../features/logs/data/logs_repository.dart';
import '../../features/processes/data/processes_repository.dart';
import '../../features/speed_test/data/speed_test_repository.dart';
import '../../features/stream/data/stream_service.dart';
import '../backoff/exponential_backoff.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../logging/app_logger.dart';

/// Background orchestrator — heartbeat 5m, processes 5m, inventory 1d,
/// speed-test 30m, commands 1m, logs ship 5m.
class AgentScheduler {
  AgentScheduler({
    required AppDatabase db,
    required AuthRepository auth,
    required HeartbeatRepository heartbeat,
    required InventoryRepository inventory,
    required ProcessesRepository processes,
    required SpeedTestRepository speedTest,
    required CommandsRepository commands,
    required LogsRepository logs,
    required AppLogger logger,
    required StreamService stream,
    void Function(int sessionId, String adminName)? onStreamStart,
    void Function()? onStreamStop,
  })  : _db = db,
        _auth = auth,
        _heartbeat = heartbeat,
        _inventory = inventory,
        _processes = processes,
        _speedTest = speedTest,
        _commands = commands,
        _logs = logs,
        _logger = logger,
        _stream = stream,
        _onStreamStart = onStreamStart,
        _onStreamStop = onStreamStop;

  final AppDatabase _db;
  final AuthRepository _auth;
  final HeartbeatRepository _heartbeat;
  final InventoryRepository _inventory;
  final ProcessesRepository _processes;
  final SpeedTestRepository _speedTest;
  final CommandsRepository _commands;
  final LogsRepository _logs;
  final AppLogger _logger;
  final StreamService _stream;
  final void Function(int, String)? _onStreamStart;
  final void Function()? _onStreamStop;
  final ExponentialBackoff _backoff = ExponentialBackoff();

  Timer? _timer;
  Duration _hbInterval = AppConfig.defaultHeartbeatInterval;
  DateTime? _lastHeartbeatAt;
  DateTime? _lastProcessesAt;
  DateTime? _lastSpeedTestAt;
  DateTime? _lastCommandsAt;
  DateTime? _lastLogsAt;

  /// UI uchun: keyingi heartbeat qachon yuborilishi.
  DateTime? get nextHeartbeatAt =>
      _lastHeartbeatAt?.add(_hbInterval);

  DateTime? get lastHeartbeatAt => _lastHeartbeatAt;
  Duration get heartbeatInterval => _hbInterval;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.schedulerTick, (_) => _tick());
    unawaited(_tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> reloadIntervalFromDb() async {
    final s = await _db.getSetting('heartbeat_interval_sec');
    final sec = int.tryParse(s ?? '') ??
        AppConfig.defaultHeartbeatInterval.inSeconds;
    _hbInterval = Duration(seconds: sec.clamp(60, 86400));
  }

  Future<void> _tick() async {
    if (!await _auth.isLoggedIn()) return;
    await reloadIntervalFromDb();
    await _flushQueue();

    final now = DateTime.now().toUtc();
    if (_dueSince(_lastHeartbeatAt, _hbInterval, now)) {
      await _doHeartbeat();
      _lastHeartbeatAt = now;
    }
    if (_dueSince(_lastProcessesAt, AppConfig.defaultProcessInterval, now)) {
      await _doProcesses();
      _lastProcessesAt = now;
    }
    if (_dueSince(_lastCommandsAt, AppConfig.defaultCommandsPollInterval, now)) {
      await _doCommandsPoll();
      _lastCommandsAt = now;
    }
    if (_dueSince(_lastSpeedTestAt, AppConfig.defaultSpeedTestInterval, now)) {
      await _doSpeedTest();
      _lastSpeedTestAt = now;
    }
    if (_dueSince(_lastLogsAt, const Duration(minutes: 5), now)) {
      await _logs.ship();
      _lastLogsAt = now;
    }
    // Inventory ichida sutkalik tekshiruv bor.
    await _inventory.sync(manual: false);
  }

  bool _dueSince(DateTime? last, Duration interval, DateTime now) {
    if (last == null) return true;
    return now.difference(last) >= interval;
  }

  Future<void> _doHeartbeat() async {
    Map<String, dynamic>? body;
    try {
      body = await _heartbeat.buildHeartbeatJson();
      if (body == null) return;
      final env = await _heartbeat.postHeartbeatJson(body);
      if (!env.success && !env.sessionRevoked) {
        await _logger.log(LogLevel.warn, 'Heartbeat rejected: ${env.message}');
      }
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Heartbeat fail, enqueue',
          error: e, stack: st);
      if (body != null) {
        await _db.enqueueSync('heartbeat', body);
      }
    }
  }

  Future<void> _doProcesses() async {
    try {
      await _processes.sync();
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Processes sync xato',
          error: e, stack: st);
    }
  }

  Future<void> _doSpeedTest() async {
    try {
      await _speedTest.runAndReport();
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Speed test xato',
          error: e, stack: st);
    }
  }

  Future<void> _doCommandsPoll() async {
    try {
      final list = await _commands.poll();
      for (final cmd in list) {
        await _logger.log(LogLevel.info, 'Server buyrug\'i: ${cmd.type}');
        switch (cmd.type) {
          case 'sync_now':
          case 'resend_all':
            await syncNow();
            break;
          case 'heartbeat':
            await _doHeartbeat();
            await _doProcesses();
            break;
          case 'inventory':
            await _inventory.sync(manual: true);
            break;
          case 'speed_test':
            await _doSpeedTest();
            break;
          case 'logout':
          case 'revoke':
            await _auth.logoutLocal();
            break;
          case 'stream_start':
            await _handleStreamStart(cmd.payload);
            break;
          case 'stream_stop':
            await _handleStreamStop();
            break;
        }
      }
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Commands poll xato',
          error: e, stack: st);
    }
  }

  Future<void> _handleStreamStart(Map<String, dynamic>? payload) async {
    final sid = payload?['session_id'];
    if (sid is! int) return;
    final adminName = (payload?['admin_name'] as String?) ?? 'Administrator';
    final fps = (payload?['fps'] as int?) ?? 3;
    final quality = (payload?['jpeg_quality'] as int?) ?? 60;
    _onStreamStart?.call(sid, adminName);
    await _stream.start(
      sessionId: sid,
      fps: fps,
      jpegQuality: quality,
    );
  }

  Future<void> _handleStreamStop() async {
    await _stream.stop(reason: 'server_command');
    _onStreamStop?.call();
  }

  Future<void> _flushQueue() async {
    final rows = await _db.pendingQueue();
    for (final row in rows) {
      final id = row['id'] as int;
      final kind = row['kind'] as String;
      final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
      final attempts = (row['attempt_count'] as int?) ?? 0;
      // 5 dan ortiq urinishdan keyin tashlab yuboramiz — heartbeat'da ko'p marta
      // duplicate xato bo'lganda queue cheksiz o'sib ketmasin.
      if (attempts >= 5) {
        await _db.deleteQueueItem(id);
        continue;
      }
      try {
        if (kind == 'heartbeat') {
          final env = await _heartbeat.postHeartbeatJson(
              Map<String, dynamic>.from(body));
          if (!env.success) {
            await _db.deleteQueueItem(id);
            continue;
          }
        }
        await _db.deleteQueueItem(id);
        await _logger.log(LogLevel.info, 'Queued $kind delivered');
      } catch (e, st) {
        final next = attempts + 1;
        final delay = _backoff.delayForAttempt(next - 1);
        final when = DateTime.now().toUtc().add(delay).toIso8601String();
        await _db.updateQueueAttempt(id, next, when);
        await _logger.log(LogLevel.warn,
            'Queue send failed ($kind), retry in ${delay.inSeconds}s',
            error: e, stack: st);
      }
    }
  }

  /// Hozir hamma narsani yuborish: heartbeat + processes + inventory + speed test.
  /// Har birini try/catch bilan o'rab, biri muvaffaqiyatsiz bo'lsa ham qolganlari ishlaydi.
  Future<void> syncNow() async {
    if (!await _auth.isLoggedIn()) return;
    try { await _flushQueue(); } catch (_) {}
    try { await _doHeartbeat(); } catch (_) {}
    _lastHeartbeatAt = DateTime.now().toUtc();
    try { await _doProcesses(); } catch (_) {}
    _lastProcessesAt = DateTime.now().toUtc();
    try { await _inventory.sync(manual: true); } catch (_) {}
    try { await _doSpeedTest(); } catch (_) {}
    _lastSpeedTestAt = DateTime.now().toUtc();
  }

  void dispose() => stop();
}
