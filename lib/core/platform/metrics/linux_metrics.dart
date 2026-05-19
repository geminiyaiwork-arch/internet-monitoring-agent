import 'dart:io';

import '../system_metrics_collector.dart';

class LinuxMetrics {
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
