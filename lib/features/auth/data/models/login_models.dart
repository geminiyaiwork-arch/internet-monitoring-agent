/// POST /api/v1/agent/login
class LoginRequest {
  LoginRequest({
    this.userId,
    required this.deviceUid,
    required this.deviceName,
    required this.machineGuid,
    required this.appVersion,
    required this.osVersion,
  });

  final int? userId;
  final String deviceUid;
  final String deviceName;
  final String machineGuid;
  final String appVersion;
  final String osVersion;

  Map<String, dynamic> toJson() => {
        if (userId != null) 'user_id': userId,
        'device_uid': deviceUid,
        'device_name': deviceName,
        'machine_guid': machineGuid,
        'app_version': appVersion,
        'os_version': osVersion,
      };
}
