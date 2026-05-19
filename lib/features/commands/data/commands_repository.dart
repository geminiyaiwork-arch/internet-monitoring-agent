import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/secure/secure_vault.dart';

/// Server tomonidan agentga buyruq berishi:
///  GET /api/v1/agent/commands -> { success, data: { commands: [ { id, type, payload } ] } }
class CommandsRepository {
  CommandsRepository({
    required ApiClient api,
    required SecureVault vault,
    required AppDatabase db,
    required AppLogger logger,
  })  : _api = api,
        _vault = vault,
        _db = db,
        _logger = logger;

  final ApiClient _api;
  final SecureVault _vault;
  final AppDatabase _db;
  final AppLogger _logger;

  Future<List<AgentCommand>> poll() async {
    final key = await _vault.readAgentKey();
    if (key == null || key.isEmpty) return const [];
    _api.syncBaseUrl();
    try {
      final env = await _api.getJson(AppConfig.commandsPath);
      if (env.sessionRevoked) {
        await _logger.log(LogLevel.warn, 'Commands: kalit bekor qilindi');
        await _vault.clearSession();
        return const [];
      }
      if (!env.success) {
        await _logger.log(LogLevel.warn, 'Commands rad: ${env.message}');
        return const [];
      }
      final list = (env.data?['commands'] as List?) ?? const [];
      final result = <AgentCommand>[];
      for (final raw in list) {
        if (raw is! Map) continue;
        final cmd = AgentCommand.fromJson(raw.cast<String, dynamic>());
        await _db.insertCommand(
          type: cmd.type,
          commandId: cmd.id,
          payloadJson:
              cmd.payload == null ? null : jsonEncode(cmd.payload),
        );
        result.add(cmd);
      }
      return result;
    } catch (e, st) {
      await _logger.log(LogLevel.error, 'Commands polling xatosi',
          error: e, stack: st);
      return const [];
    }
  }
}

class AgentCommand {
  AgentCommand({
    required this.id,
    required this.type,
    this.payload,
  });

  final String id;
  final String type;
  final Map<String, dynamic>? payload;

  factory AgentCommand.fromJson(Map<String, dynamic> json) => AgentCommand(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        payload: json['payload'] is Map<String, dynamic>
            ? json['payload'] as Map<String, dynamic>
            : null,
      );
}
