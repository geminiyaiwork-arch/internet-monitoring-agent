import 'dart:io';

import '../system_metrics_collector.dart';

class LinuxMetrics {
  /// Mount qilingan disklar ro'yxati ({mount, fs, total_mb, free_mb}).
  static List<Map<String, dynamic>> listDisks() {
    if (!Platform.isLinux) return const [];
    final result = <Map<String, dynamic>>[];
    try {
      // df -k -T -x tmpfs -x devtmpfs -x squashfs -x overlay -x proc -x sysfs -x cgroup
      final res = Process.runSync('df', ['-k', '-T', '-x', 'tmpfs', '-x', 'devtmpfs', '-x', 'squashfs', '-x', 'overlay']);
      final lines = res.stdout.toString().split('\n');
      for (var i = 1; i < lines.length; i++) {
        final parts = lines[i].split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        if (parts.length < 7) continue;
        final fs = parts[1];
        final totalKb = int.tryParse(parts[2]) ?? 0;
        final usedKb = int.tryParse(parts[3]) ?? 0;
        final mount = parts[6];
        if (totalKb <= 0) continue;
        // /boot/efi va /snap kabilarni o'tkazib yuborish
        if (mount.startsWith('/boot') || mount.startsWith('/snap') || mount.startsWith('/run')) continue;
        result.add({
          'mount': mount,
          'fs': fs,
          'total_mb': (totalKb ~/ 1024),
          'free_mb': ((totalKb - usedKb) ~/ 1024).clamp(0, totalKb ~/ 1024),
        });
      }
    } catch (_) {}
    return result;
  }

  /// "wifi" yoki "ethernet" yoki null
  static String? networkType() {
    if (!Platform.isLinux) return null;
    try {
      // /sys/class/net/* — wireless papka borligini tekshirish
      final netDir = Directory('/sys/class/net');
      if (!netDir.existsSync()) return null;
      String? type;
      for (final iface in netDir.listSync()) {
        final name = iface.path.split('/').last;
        if (name == 'lo' || name.startsWith('docker') || name.startsWith('veth') || name.startsWith('br-')) continue;
        // operstate=up bo'lganini tanlash
        try {
          final op = File('${iface.path}/operstate').readAsStringSync().trim();
          if (op != 'up') continue;
        } catch (_) { continue; }
        if (Directory('${iface.path}/wireless').existsSync()) {
          return 'wifi';
        }
        type ??= 'ethernet';
      }
      return type;
    } catch (_) {
      return null;
    }
  }


  static int uptimeSeconds() {
    if (!Platform.isLinux) return 0;
    try {
      final raw = File('/proc/uptime').readAsStringSync().trim();
      final first = raw.split(RegExp(r'\s+')).first;
      return double.parse(first).toInt();
    } catch (_) {
      return 0;
    }
  }

  static ResourceSnapshot snapshot() {
    if (!Platform.isLinux) return ResourceSnapshot.empty;
    int ramTotalMb = 1;
    int ramUsedMb = 0;
    int diskTotalMb = 1;
    int diskFreeMb = 0;
    int cpuPct = 0;
    try {
      final mem = File('/proc/meminfo').readAsStringSync();
      int kb(String key) {
        final m =
            RegExp('$key:\\s+(\\d+)\\s+kB', multiLine: true).firstMatch(mem);
        return int.tryParse(m?.group(1) ?? '0') ?? 0;
      }

      final totalKb = kb('MemTotal');
      final availKb = kb('MemAvailable');
      ramTotalMb = (totalKb ~/ 1024).clamp(1, 1 << 20);
      final availMb = (availKb ~/ 1024).clamp(0, ramTotalMb);
      ramUsedMb = (ramTotalMb - availMb).clamp(0, ramTotalMb);
    } catch (_) {}

    try {
      final df = Process.runSync('df', ['-k', '/']);
      final dfLines = df.stdout.toString().split('\n');
      if (dfLines.length >= 2) {
        final parts = dfLines[1]
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.length >= 4) {
          final totalKb = int.tryParse(parts[1]) ?? 0;
          final freeKb = int.tryParse(parts[3]) ?? 0;
          diskTotalMb = (totalKb ~/ 1024).clamp(1, 1 << 30);
          diskFreeMb = (freeKb ~/ 1024).clamp(0, diskTotalMb);
        }
      }
    } catch (_) {}

    try {
      final stat = File('/proc/loadavg').readAsStringSync().trim();
      final load1 = double.tryParse(stat.split(' ').first) ?? 0;
      final cores = Platform.numberOfProcessors;
      cpuPct = ((load1 / cores) * 100).clamp(0, 100).round();
    } catch (_) {}

    return ResourceSnapshot(
      ramTotalMb: ramTotalMb,
      ramUsedMb: ramUsedMb,
      diskTotalMb: diskTotalMb,
      diskFreeMb: diskFreeMb,
      cpuUsagePercent: cpuPct,
    );
  }
}
