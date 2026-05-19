import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqflite.dart';

import '../config/app_config.dart';

class AppDatabase {
  AppDatabase(this._db);

  final Database _db;

  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    final path = p.join(dir.path, 'ima', 'agent.db');
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: _create,
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await _createSpeedAndCommands(db);
        }
      },
    );
    return AppDatabase(db);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE auth_session (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  last_login_at TEXT,
  last_success_sync TEXT,
  inventory_last_sent_at TEXT,
  inventory_last_update TEXT,
  processes_last_sent_at TEXT,
  speedtest_last_sent_at TEXT
)
''');
    await db.execute('''
CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE inventory_cache (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  display_name TEXT NOT NULL,
  display_version TEXT,
  publisher TEXT,
  install_date TEXT,
  record_hash TEXT NOT NULL UNIQUE
)
''');
    await db.execute('''
CREATE TABLE logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  level TEXT NOT NULL,
  message TEXT NOT NULL,
  context TEXT,
  created_at TEXT NOT NULL
)
''');
    await _createSpeedAndCommands(db);
    await db.insert('auth_session', {
      'id': 1,
      'last_login_at': null,
      'last_success_sync': null,
      'inventory_last_sent_at': null,
      'inventory_last_update': null,
      'processes_last_sent_at': null,
      'speedtest_last_sent_at': null,
    });
  }

  static Future<void> _createSpeedAndCommands(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS speed_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tested_at TEXT NOT NULL,
  download_mbps REAL,
  upload_mbps REAL,
  latency_ms INTEGER,
  bytes_down INTEGER,
  bytes_up INTEGER,
  server TEXT,
  error TEXT
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS commands_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  command_id TEXT,
  type TEXT NOT NULL,
  payload TEXT,
  received_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  result TEXT
)
''');
  }

  Future<void> close() => _db.close();

  // ===== settings =====
  Future<String?> getSetting(String key) async {
    final rows = await _db
        .query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    await _db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ===== auth_session =====
  Future<void> updateAuthSession({
    String? lastLoginAt,
    String? lastSuccessSync,
    String? inventoryLastSentAt,
    String? inventoryLastUpdate,
    String? processesLastSentAt,
    String? speedtestLastSentAt,
  }) async {
    final map = <String, Object?>{};
    if (lastLoginAt != null) map['last_login_at'] = lastLoginAt;
    if (lastSuccessSync != null) map['last_success_sync'] = lastSuccessSync;
    if (inventoryLastSentAt != null) {
      map['inventory_last_sent_at'] = inventoryLastSentAt;
    }
    if (inventoryLastUpdate != null) {
      map['inventory_last_update'] = inventoryLastUpdate;
    }
    if (processesLastSentAt != null) {
      map['processes_last_sent_at'] = processesLastSentAt;
    }
    if (speedtestLastSentAt != null) {
      map['speedtest_last_sent_at'] = speedtestLastSentAt;
    }
    if (map.isEmpty) return;
    await _db.update('auth_session', map, where: 'id = 1');
  }

  Future<Map<String, Object?>> getAuthSessionRow() async {
    final rows = await _db.query('auth_session', where: 'id = 1', limit: 1);
    return rows.isEmpty ? {} : rows.first;
  }

  // ===== sync_queue =====
  Future<int> enqueueSync(String kind, Map<String, dynamic> body) async {
    await _trimQueueIfNeeded();
    final now = DateTime.now().toUtc().toIso8601String();
    return _db.insert('sync_queue', {
      'kind': kind,
      'body': jsonEncode(body),
      'created_at': now,
      'attempt_count': 0,
      'next_attempt_at': now,
    });
  }

  Future<List<Map<String, Object?>>> pendingQueue({int limit = 50}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return _db.query(
      'sync_queue',
      where: 'next_attempt_at <= ?',
      whereArgs: [now],
      orderBy: 'id ASC',
      limit: limit,
    );
  }

  Future<void> deleteQueueItem(int id) =>
      _db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);

  Future<void> updateQueueAttempt(
      int id, int attemptCount, String nextAttemptIso) async {
    await _db.update(
      'sync_queue',
      {'attempt_count': attemptCount, 'next_attempt_at': nextAttemptIso},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _trimQueueIfNeeded() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM sync_queue');
    final c = (r.first['c'] as int?) ?? 0;
    if (c < AppConfig.maxSyncQueueRows) return;
    final excess = c - AppConfig.maxSyncQueueRows + 1;
    await _db.rawDelete(
      'DELETE FROM sync_queue WHERE id IN (SELECT id FROM sync_queue ORDER BY id ASC LIMIT ?)',
      [excess],
    );
  }

  // ===== logs =====
  Future<void> insertLog(String level, String message, {String? context}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.insert('logs', {
      'level': level,
      'message': message,
      'context': context,
      'created_at': now,
    });
    await _trimLogsIfNeeded();
    await _purgeOldLogs();
  }

  Future<void> _trimLogsIfNeeded() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS c FROM logs');
    final c = (r.first['c'] as int?) ?? 0;
    if (c <= AppConfig.maxLogRows) return;
    final excess = c - AppConfig.maxLogRows;
    await _db.rawDelete(
      'DELETE FROM logs WHERE id IN (SELECT id FROM logs ORDER BY id ASC LIMIT ?)',
      [excess],
    );
  }

  Future<void> _purgeOldLogs() async {
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: AppConfig.logRetentionDays))
        .toIso8601String();
    await _db.delete('logs', where: 'created_at < ?', whereArgs: [cutoff]);
  }

  Future<List<Map<String, Object?>>> recentLogs({int limit = 200}) async {
    return _db.query('logs', orderBy: 'id DESC', limit: limit);
  }

  Future<List<Map<String, Object?>>> unsentLogs({int limit = 200}) async {
    return _db.query('logs', orderBy: 'id ASC', limit: limit);
  }

  Future<void> deleteLogsByIds(List<int> ids) async {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db
        .rawDelete('DELETE FROM logs WHERE id IN ($placeholders)', ids);
  }

  // ===== inventory_cache =====
  Future<void> clearInventoryCache() => _db.delete('inventory_cache');

  Future<List<Map<String, Object?>>> allInventoryCache() =>
      _db.query('inventory_cache');

  Future<void> upsertInventoryRows(List<Map<String, Object?>> rows) async {
    final batch = _db.batch();
    for (final r in rows) {
      batch.insert('inventory_cache', r,
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ===== speed_history =====
  Future<int> insertSpeedHistory(Map<String, Object?> row) =>
      _db.insert('speed_history', row);

  Future<List<Map<String, Object?>>> recentSpeedHistory({int limit = 50}) =>
      _db.query('speed_history', orderBy: 'id DESC', limit: limit);

  // ===== commands_log =====
  Future<int> insertCommand({
    required String type,
    String? commandId,
    String? payloadJson,
  }) {
    return _db.insert('commands_log', {
      'command_id': commandId,
      'type': type,
      'payload': payloadJson,
      'received_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'pending',
    });
  }

  Future<void> markCommand(int id, String status, {String? result}) {
    return _db.update(
      'commands_log',
      {'status': status, if (result != null) 'result': result},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
