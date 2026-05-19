import 'dart:convert';
import 'dart:io';

import 'models/process_models.dart';

abstract class ProcessScanner {
  Future<List<ProcessInfoDto>> scan();
}

ProcessScanner createProcessScanner() {
  if (Platform.isWindows) return WindowsProcessScanner();
  if (Platform.isMacOS) return UnixProcessScanner(macos: true);
  if (Platform.isLinux) return LinuxProcProcessScanner();
  return _EmptyScanner();
}

class _EmptyScanner implements ProcessScanner {
  @override
  Future<List<ProcessInfoDto>> scan() async => const [];
}

// =================== Windows: PowerShell ===================
class WindowsProcessScanner implements ProcessScanner {
  @override
  Future<List<ProcessInfoDto>> scan() async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue';
Get-CimInstance Win32_Process | ForEach-Object {
  $p = $_;
  $owner = (Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction SilentlyContinue);
  [PSCustomObject]@{
    pid       = [int]$p.ProcessId
    name      = $p.Name
    exe_path  = $p.ExecutablePath
    mem_mb    = [int]([Math]::Round(($p.WorkingSetSize / 1MB)))
    started   = $p.CreationDate
    user      = if ($owner) { ($owner.Domain + "\" + $owner.User) } else { $null }
    cmdline   = $p.CommandLine
  }
} | ConvertTo-Json -Compress
''';
    try {
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]).timeout(const Duration(seconds: 30));
      if (res.exitCode != 0) return const [];
      final raw = res.stdout.toString().trim();
      if (raw.isEmpty) return const [];
      final decoded = json.decode(raw);
      final list = decoded is List ? decoded : [decoded];
      return list.whereType<Map>().map((m) {
        return ProcessInfoDto(
          pid: (m['pid'] as num?)?.toInt() ?? 0,
          name: m['name']?.toString() ?? '',
          executablePath: m['exe_path']?.toString(),
          memoryMb: (m['mem_mb'] as num?)?.toInt(),
          startedAt: m['started']?.toString(),
          user: m['user']?.toString(),
          commandLine: m['cmdline']?.toString(),
        );
      }).where((p) => p.pid > 0 && p.name.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }
}

// =================== macOS: ps ===================
class UnixProcessScanner implements ProcessScanner {
  UnixProcessScanner({this.macos = false});

  final bool macos;

  @override
  Future<List<ProcessInfoDto>> scan() async {
    try {
      final res = await Process.run('ps', [
        '-Ao',
        'pid=,comm=,%cpu=,rss=,lstart=,user=,args=',
      ]).timeout(const Duration(seconds: 15));
      if (res.exitCode != 0) return const [];
      final lines = res.stdout.toString().split('\n');
      final result = <ProcessInfoDto>[];
      for (final line in lines) {
        final t = line.trim();
        if (t.isEmpty) continue;
        // lstart has spaces: "Mon Apr 23 10:00:00 2026"
        // Split first 4 fields manually, the rest is lstart(5w) + user(1w) + args(rest).
        final parts = t.split(RegExp(r'\s+'));
        if (parts.length < 11) continue;
        final pid = int.tryParse(parts[0]) ?? 0;
        final name = parts[1];
        final cpu = double.tryParse(parts[2]);
        final rssKb = int.tryParse(parts[3]);
        final lstart = parts.sublist(4, 9).join(' ');
        final user = parts[9];
        final args = parts.sublist(10).join(' ');
        if (pid <= 0 || name.isEmpty) continue;
        result.add(ProcessInfoDto(
          pid: pid,
          name: name,
          executablePath: args.startsWith('/') ? args.split(' ').first : null,
          cpuPercent: cpu,
          memoryMb: rssKb == null ? null : (rssKb / 1024).round(),
          startedAt: lstart,
          user: user,
          commandLine: args,
        ));
      }
      return result;
    } catch (_) {
      return const [];
    }
  }
}

// =================== Linux: /proc ===================
class LinuxProcProcessScanner implements ProcessScanner {
  @override
  Future<List<ProcessInfoDto>> scan() async {
    final result = <ProcessInfoDto>[];
    final proc = Directory('/proc');
    if (!proc.existsSync()) return const [];
    for (final entity in proc.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.path.split('/').last;
      final pid = int.tryParse(name);
      if (pid == null) continue;
      try {
        final stat = File('${entity.path}/stat').readAsStringSync();
        // stat format: pid (comm) state ppid ...
        final lp = stat.indexOf('(');
        final rp = stat.lastIndexOf(')');
        if (lp < 0 || rp < 0) continue;
        final comm = stat.substring(lp + 1, rp);
        final after = stat.substring(rp + 2).split(' ');
        // starttime is field 22 of stat (after the comm); after stat[2] = state, [3] = ppid, ...
        // index in after-list (after closing paren) starts from state.
        final starttimeStr = after.length > 19 ? after[19] : null;

        // VmRSS
        int? memMb;
        try {
          final status = File('${entity.path}/status').readAsStringSync();
          final m = RegExp(r'VmRSS:\s+(\d+)\s+kB').firstMatch(status);
          if (m != null) {
            memMb = (int.parse(m.group(1)!) / 1024).round();
          }
        } catch (_) {}

        // cmdline
        String? cmdline;
        try {
          final raw = File('${entity.path}/cmdline').readAsBytesSync();
          if (raw.isNotEmpty) {
            cmdline = String.fromCharCodes(raw.map((b) => b == 0 ? 32 : b))
                .trim();
          }
        } catch (_) {}

        // exe (symlink)
        String? exe;
        try {
          exe = File('${entity.path}/exe').resolveSymbolicLinksSync();
        } catch (_) {}

        // owner (uid)
        String? user;
        try {
          final status = File('${entity.path}/status').readAsStringSync();
          final m = RegExp(r'Uid:\s+(\d+)').firstMatch(status);
          if (m != null) user = 'uid:${m.group(1)}';
        } catch (_) {}

        result.add(ProcessInfoDto(
          pid: pid,
          name: comm,
          executablePath: exe,
          memoryMb: memMb,
          startedAt: starttimeStr,
          user: user,
          commandLine: cmdline,
        ));
      } catch (_) {
        continue;
      }
    }
    return result;
  }
}
