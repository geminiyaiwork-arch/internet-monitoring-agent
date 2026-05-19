/// Server javob konverti (spec bo'yicha standard envelope).
///
/// ```
/// {
///   "success": true,
///   "message": "OK",
///   "data": {},
///   "key": null,             // server key rotation qilsa shu yerda
///   "server_time": "2026-04-23T10:10:02Z",
///   "next_interval": 600,    // keyingi heartbeat soniyada
///   "errors": null
/// }
/// ```
class ApiEnvelope {
  ApiEnvelope({
    required this.success,
    this.message,
    this.key,
    this.serverTime,
    this.nextIntervalSec,
    this.sessionRevoked = false,
    this.data,
    this.errors,
    this.raw,
  });

  final bool success;
  final String? message;
  final String? key;
  final String? serverTime;
  final int? nextIntervalSec;
  final bool sessionRevoked;
  final Map<String, dynamic>? data;
  final dynamic errors;
  final Map<String, dynamic>? raw;

  factory ApiEnvelope.fromJson(Map<String, dynamic> json) {
    final revoked = json['revoked'] == true ||
        json['logout'] == true ||
        json['session_revoked'] == true ||
        json['key_revoked'] == true;
    return ApiEnvelope(
      success: json['success'] == true,
      message: json['message']?.toString(),
      key: (json['key'] ?? json['assigned_key'])?.toString(),
      serverTime: json['server_time']?.toString(),
      nextIntervalSec: _parseInt(json['next_interval']),
      sessionRevoked: revoked,
      data: json['data'] is Map<String, dynamic>
          ? json['data'] as Map<String, dynamic>
          : null,
      errors: json['errors'],
      raw: json,
    );
  }

  static int? _parseInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse(v.toString());
  }
}
