import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'metrics/linux_metrics.dart';
import 'metrics/windows_metrics.dart';

class ResourceSnapshot {
  const ResourceSnapshot({
    required this.ramTotalMb,
    required this.ramUsedMb,
    required this.diskTotalMb,
    required this.diskFreeMb,
    required this.cpuUsagePercent,
  });

  final int ramTotalMb;
  final int ramUsedMb;
  final int diskTotalMb;
  final int diskFreeMb;
  final int cpuUsagePercent;

  static const empty = ResourceSnapshot(
    ramTotalMb: 0,
    ramUsedMb: 0,
    diskTotalMb: 0,
    diskFreeMb: 0,
    cpuUsagePercent: 0,
  );
}

/// Platforma-agnostik tarmoq + tizim metrikalar yig'uvchisi.
class SystemMetricsCollector {
  SystemMetricsCollector({Dio? publicIpClient})
      : _publicIpDio = publicIpClient ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
            ));

  final Dio _publicIpDio;

  Future<String> networkStatusLabel() async {
    final r = await Connectivity().checkConnectivity();
    if (r.contains(ConnectivityResult.none) || r.isEmpty) {
      return 'offline';
    }
    return 'online';
  }

  Future<String> primaryLocalIp() async {
    try {
      final wifi = await NetworkInfo().getWifiIP();
      if (wifi != null && wifi.isNotEmpty && wifi != '0.0.0.0') return wifi;
    } catch (_) {}
    try {
      for (final iface in await NetworkInterface.list()) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '0.0.0.0';
  }

  Future<String?> fetchPublicIp() async {
    try {
      final res = await _publicIpDio
          .get<Map<String, dynamic>>('https://api.ipify.org?format=json');
      return res.data?['ip']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Tizim ishlagan vaqt (soniya).
  int uptimeSeconds() {
    if (Platform.isWindows) return WindowsMetrics.uptimeSeconds();
    if (Platform.isLinux) return LinuxMetrics.uptimeSeconds();
    return 0;
  }

  ResourceSnapshot readResources() {
    if (Platform.isWindows) return WindowsMetrics.snapshot();
    if (Platform.isLinux) return LinuxMetrics.snapshot();
    return ResourceSnapshot.empty;
  }

  List<Map<String, dynamic>> listDisks() {
    if (Platform.isWindows) return WindowsMetrics.listDisks();
    if (Platform.isLinux) return LinuxMetrics.listDisks();
    return const [];
  }

  String? detailedNetworkType() {
    if (Platform.isWindows) return WindowsMetrics.networkType();
    if (Platform.isLinux) return LinuxMetrics.networkType();
    return null;
  }
}
