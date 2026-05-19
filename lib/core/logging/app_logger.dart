import 'package:flutter/foundation.dart';

import '../database/app_database.dart';

enum LogLevel { debug, info, warn, error }

/// Persists important events to SQLite and mirrors to debug console (TZ #15, #70).
class AppLogger {
  AppLogger(this._db);

  final AppDatabase _db;

  Future<void> log(
    LogLevel level,
    String message, {
    String? context,
    Object? error,
    StackTrace? stack,
  }) async {
    if (kDebugMode) {
      // Avoid sensitive payloads in debug (TZ #70).
      debugPrint('[${level.name}] $message${context != null ? ' | $context' : ''}');
      if (error != null) debugPrint('$error');
      if (stack != null) debugPrint('$stack');
    }
    if (level == LogLevel.debug && kReleaseMode) {
      return;
    }
    await _db.insertLog(level.name, message, context: context);
  }
}
