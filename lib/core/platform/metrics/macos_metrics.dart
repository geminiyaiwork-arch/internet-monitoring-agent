import 'dart:io';

import '../system_metrics_collector.dart';

class MacOsMetrics {
  static int uptimeSeconds() {
    if (!Platform.isMacOS) return 0;
    try {
      // `sysctl -n kern.boottime` -> "{ sec = 1716000000, usec = 0 } ..."
      final res = Process.runSync('sysctl', ['-n', 'kern.boottime']);
      final out = res.stdout.toString();
      final m = RegExp(r'sec\s*=\s*(\d+)').firstMatch(out);
      if (m == null) return 0;
      final boot = int.parse(m.group(1)!);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return (now - boot).clamp(0, 1 << 31);
    } catch (_) {
      return 0;
    }
  }

  static ResourceSnapshot snapshot() {
    if (!Platform.isMacOS) return ResourceSnapshot.empty;
    try {
      // RAM total bytes
      final memRes = Process.runSync('sysctl', ['-n', 'hw.memsize']);
      final totalBytes = int.tryParse(memRes.stdout.toString().trim()) ?? 0;

      // RAM ishlatilgan: vm_stat -> page size va active/wired/...
      final vm = Process.runSync('vm_stat', []);
      final vmOut = vm.stdout.toString();
      final pageSizeMatch =
          RegExp(r'page size of (\d+) bytes').firstMatch(vmOut);
      final pageSize =
          int.tryParse(pageSizeMatch?.group(1) ?? '4096') ?? 4096;
      int parseCount(String key) {
        final m =
            RegExp('$key:\\s*(\\d+)', multiLine: true).firstMatch(vmOut);
        return int.tryParse(m?.group(1) ?? '0') ?? 0;
      }

      final active = parseCount('Pages active');
      final wired = parseCount('Pages wired down');
      final compressed = parseCount('Pages occupied by compressor');
      final usedBytes = (active + wired + compressed) * pageSize;

      // Disk: df -k /
      final df = Process.runSync('df', ['-k', '/']);
      final dfLines = df.stdout.toString().split('\n');
      int diskTotalKb = 0;
      int diskFreeKb = 0;
      if (dfLines.length >= 2) {
        final parts =
            dfLines[1].split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
        if (parts.length >= 4) {
          diskTotalKb = int.tryParse(parts[1]) ?? 0;
          diskFreeKb = int.tryParse(parts[3]) ?? 0;
        }
      }

      // CPU usage (load average -> percentage rough)
      final loadRes = Process.runSync('sysctl', ['-n', 'vm.loadavg']);
      final loadOut = loadRes.stdout.toString();
      final loadMatch = RegExp(r'([\d.]+)').firstMatch(loadOut);
      final load1 = double.tryParse(loadMatch?.group(1) ?? '0') ?? 0;
      final coreRes = Process.runSync('sysctl', ['-n', 'hw.ncpu']);
      final cores = int.tryParse(coreRes.stdout.toString().trim()) ?? 1;
      final cpuPct = ((load1 / cores) * 100).clamp(0, 100).round();

      final ramTotalMb = (totalBytes ~/ (1024 * 1024)).clamp(1, 1 << 20);
      final ramUsedMb = (usedBytes ~/ (1024 * 1024)).clamp(0, ramTotalMb);
      final diskTotalMb = (diskTotalKb ~/ 1024).clamp(1, 1 << 30);
      final diskFreeMb = (diskFreeKb ~/ 1024).clamp(0, diskTotalMb);
      return ResourceSnapshot(
        ramTotalMb: ramTotalMb,
        ramUsedMb: ramUsedMb,
        diskTotalMb: diskTotalMb,
        diskFreeMb: diskFreeMb,
        cpuUsagePercent: cpuPct,
      );
    } catch (_) {
      return ResourceSnapshot.empty;
    }
  }
}
