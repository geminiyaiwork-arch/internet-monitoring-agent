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
    this.networkType,
    required this.timestamp,
    required this.uptime,
    required this.ramTotalMb,
    required this.ramUsedMb,
    required this.diskTotalMb,
    required this.diskFreeMb,
    required this.cpuUsage,
    this.disks = const [],
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
  final String? networkType; // "wifi" yoki "ethernet"
  final String timestamp;
  final int uptime;
  final int ramTotalMb;
  final int ramUsedMb;
  final int diskTotalMb;
  final int diskFreeMb;
  final int cpuUsage;
  final List<DiskInfo> disks;

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
        if (networkType != null) 'network_type': networkType,
        'timestamp': timestamp,
        'uptime_sec': uptime,
        'ram_total_mb': ramTotalMb,
        'ram_used_mb': ramUsedMb,
        'disk_total_mb': diskTotalMb,
        'disk_free_mb': diskFreeMb,
        'cpu_usage_percent': cpuUsage,
        if (disks.isNotEmpty) 'disks': disks.map((d) => d.toJson()).toList(),
      };
}

class DiskInfo {
  DiskInfo({
    required this.mount,
    this.label,
    this.fs,
    required this.totalMb,
    required this.freeMb,
  });

  final String mount;
  final String? label;
  final String? fs;
  final int totalMb;
  final int freeMb;

  Map<String, dynamic> toJson() => {
        'mount': mount,
        if (label != null) 'label': label,
        if (fs != null) 'fs': fs,
        'total_mb': totalMb,
        'free_mb': freeMb,
      };
}
