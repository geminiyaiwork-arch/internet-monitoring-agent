/// POST /api/v1/agent/heartbeat
class HeartbeatRequest {
  HeartbeatRequest({
    required this.deviceUid,
    required this.deviceName,
    required this.computerUsername,
    required this.osName,
    required this.osVersion,
    required this.appVersion,
    required this.localIp,
    this.publicIp,
    required this.networkStatus,
    required this.timestamp,
    required this.uptime,
    required this.ramTotalMb,
    required this.ramUsedMb,
    required this.diskTotalMb,
    required this.diskFreeMb,
    required this.cpuUsage,
  });

  final String deviceUid;
  final String deviceName;
  final String computerUsername;
  final String osName;
  final String osVersion;
  final String appVersion;
  final String localIp;
  final String? publicIp;
  final String networkStatus;
  final String timestamp;
  final int uptime;
  final int ramTotalMb;
  final int ramUsedMb;
  final int diskTotalMb;
  final int diskFreeMb;
  final int cpuUsage;

  Map<String, dynamic> toJson() => {
        'device_uid': deviceUid,
        'device_name': deviceName,
        'computer_username': computerUsername,
        'os_name': osName,
        'os_version': osVersion,
        'app_version': appVersion,
        'local_ip': localIp,
        if (publicIp != null) 'public_ip': publicIp,
        'network_status': networkStatus,
        'timestamp': timestamp,
        'uptime': uptime,
        'ram_total': ramTotalMb,
        'ram_used': ramUsedMb,
        'disk_total': diskTotalMb,
        'disk_free': diskFreeMb,
        'cpu_usage': cpuUsage,
      };
}
