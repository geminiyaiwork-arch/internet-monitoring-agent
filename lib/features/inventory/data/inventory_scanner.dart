import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models/inventory_models.dart';

abstract class InventoryScanner {
  Future<List<InstalledAppDto>> scan();
}

InventoryScanner createInventoryScanner() {
  if (Platform.isWindows) return WindowsInventoryScanner();
  if (Platform.isMacOS) return MacOsInventoryScanner();
  if (Platform.isLinux) return LinuxInventoryScanner();
  return _EmptyScanner();
}

class _EmptyScanner implements InventoryScanner {
  @override
  Future<List<InstalledAppDto>> scan() async => const [];
}

// =================== Windows ===================
class WindowsInventoryScanner implements InventoryScanner {
  static const _hives = <List<String>>[
    ['HKLM', r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'],
    ['HKLM', r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'],
    ['HKCU', r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'],
  ];

  @override
  Future<List<InstalledAppDto>> scan() async {
    final map = <String, InstalledAppDto>{};
    for (final h in _hives) {
      try {
        final res = await Process.run('reg', [
          'query',
          '${h[0]}\\${h[1]}',
          '/s',
        ]);
        if (res.exitCode != 0) continue;
        final text = res.stdout.toString();
        _parseRegBlocks(text, map);
      } catch (_) {
        continue;
      }
    }
    return map.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  void _parseRegBlocks(String text, Map<String, InstalledAppDto> sink) {
    final blocks = text.split(RegExp(r'\r?\n\r?\n'));
    for (final block in blocks) {
      String? name;
      String? version;
      String? publisher;
      String? date;
      String? path;
      for (final line in block.split(RegExp(r'\r?\n'))) {
        final t = line.trim();
        if (t.startsWith('DisplayName ')) {
          name = _regValue(t);
        } else if (t.startsWith('DisplayVersion ')) {
          version = _regValue(t);
        } else if (t.startsWith('Publisher ')) {
          publisher = _regValue(t);
        } else if (t.startsWith('InstallDate ')) {
          date = _regValue(t);
        } else if (t.startsWith('InstallLocation ')) {
          path = _regValue(t);
        }
      }
      if (name != null && name.trim().isNotEmpty) {
        final dto = InstalledAppDto(
          displayName: name.trim(),
          displayVersion: version,
          publisher: publisher,
          installDate: date,
          installPath: path,
          source: 'registry',
        );
        sink[dto.computeHash()] = dto;
      }
    }
  }

  String? _regValue(String line) {
    final m = RegExp(r'REG_(?:SZ|EXPAND_SZ|DWORD)\s+(.*)').firstMatch(line);
    final v = m?.group(1)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}

// =================== macOS ===================
class MacOsInventoryScanner implements InventoryScanner {
  @override
  Future<List<InstalledAppDto>> scan() async {
    final map = <String, InstalledAppDto>{};

    // 1) /Applications va ~/Applications papkalaridagi .app
    for (final root in ['/Applications', '${Platform.environment['HOME']}/Applications']) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is Directory && entity.path.endsWith('.app')) {
          final infoPlist = File(p.join(entity.path, 'Contents', 'Info.plist'));
          String? version;
          String? bundleId;
          if (infoPlist.existsSync()) {
            try {
              final res = await Process.run('defaults', [
                'read',
                p.join(entity.path, 'Contents', 'Info'),
                'CFBundleShortVersionString',
              ]);
              if (res.exitCode == 0) version = res.stdout.toString().trim();
            } catch (_) {}
            try {
              final res = await Process.run('defaults', [
                'read',
                p.join(entity.path, 'Contents', 'Info'),
                'CFBundleIdentifier',
              ]);
              if (res.exitCode == 0) bundleId = res.stdout.toString().trim();
            } catch (_) {}
          }
          final dto = InstalledAppDto(
            displayName: p.basenameWithoutExtension(entity.path),
            displayVersion: version,
            publisher: bundleId,
            installPath: entity.path,
            source: 'applications',
          );
          map[dto.computeHash()] = dto;
        }
      }
    }

    // 2) system_profiler SPApplicationsDataType (qo'shimcha)
    try {
      final res = await Process.run('system_profiler', [
        'SPApplicationsDataType',
        '-json',
        '-detailLevel',
        'mini',
      ]).timeout(const Duration(seconds: 30));
      if (res.exitCode == 0) {
        final decoded = json.decode(res.stdout.toString());
        final items = (decoded['SPApplicationsDataType'] as List?) ?? const [];
        for (final raw in items) {
          if (raw is! Map) continue;
          final name = raw['_name']?.toString();
          if (name == null || name.isEmpty) continue;
          final dto = InstalledAppDto(
            displayName: name,
            displayVersion: raw['version']?.toString(),
            publisher: raw['obtained_from']?.toString(),
            installDate: raw['lastModified']?.toString(),
            installPath: raw['path']?.toString(),
            source: 'system_profiler',
          );
          map[dto.computeHash()] = dto;
        }
      }
    } catch (_) {}

    return map.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }
}

// =================== Linux ===================
class LinuxInventoryScanner implements InventoryScanner {
  @override
  Future<List<InstalledAppDto>> scan() async {
    final map = <String, InstalledAppDto>{};

    // 1) dpkg (Debian/Ubuntu)
    await _runIf('dpkg-query', ['-W', '-f', r'${Package}|${Version}|${Maintainer}|${Status}' '\n'],
        onSuccess: (out) {
      for (final line in out.split('\n')) {
        final parts = line.split('|');
        if (parts.length < 4) continue;
        if (!parts[3].contains('installed')) continue;
        final dto = InstalledAppDto(
          displayName: parts[0],
          displayVersion: parts[1].isEmpty ? null : parts[1],
          publisher: parts[2].isEmpty ? null : parts[2],
          source: 'dpkg',
        );
        map[dto.computeHash()] = dto;
      }
    });

    // 2) rpm (Fedora/RHEL)
    await _runIf('rpm', ['-qa', '--queryformat', r'%{NAME}|%{VERSION}|%{VENDOR}|%{INSTALLTIME:date}' '\n'],
        onSuccess: (out) {
      for (final line in out.split('\n')) {
        final parts = line.split('|');
        if (parts.length < 4 || parts[0].isEmpty) continue;
        final dto = InstalledAppDto(
          displayName: parts[0],
          displayVersion: parts[1].isEmpty ? null : parts[1],
          publisher: parts[2].isEmpty ? null : parts[2],
          installDate: parts[3].isEmpty ? null : parts[3],
          source: 'rpm',
        );
        map[dto.computeHash()] = dto;
      }
    });

    // 3) flatpak
    await _runIf('flatpak', ['list', '--app', '--columns=name,version,origin'],
        onSuccess: (out) {
      for (final line in out.split('\n').skip(0)) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('Name')) continue;
        final parts = t.split(RegExp(r'\t+|\s{2,}'));
        if (parts.isEmpty) continue;
        final dto = InstalledAppDto(
          displayName: parts[0],
          displayVersion: parts.length > 1 ? parts[1] : null,
          publisher: parts.length > 2 ? parts[2] : null,
          source: 'flatpak',
        );
        map[dto.computeHash()] = dto;
      }
    });

    // 4) snap
    await _runIf('snap', ['list'], onSuccess: (out) {
      final lines = out.split('\n');
      for (var i = 1; i < lines.length; i++) {
        final parts = lines[i]
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();
        if (parts.length < 2) continue;
        final dto = InstalledAppDto(
          displayName: parts[0],
          displayVersion: parts[1],
          publisher: parts.length > 4 ? parts[4] : null,
          source: 'snap',
        );
        map[dto.computeHash()] = dto;
      }
    });

    // 5) .desktop fayllar (umumiy katalog)
    for (final dirPath in const [
      '/usr/share/applications',
      '/usr/local/share/applications',
    ]) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync()) {
        if (file is! File || !file.path.endsWith('.desktop')) continue;
        try {
          final lines = file.readAsLinesSync();
          String? name;
          String? exec;
          for (final l in lines) {
            if (l.startsWith('Name=')) {
              name ??= l.substring(5).trim();
            } else if (l.startsWith('Exec=')) {
              exec ??= l.substring(5).trim();
            }
          }
          if (name == null || name.isEmpty) continue;
          final dto = InstalledAppDto(
            displayName: name,
            installPath: exec,
            source: 'desktop',
          );
          map.putIfAbsent(dto.computeHash(), () => dto);
        } catch (_) {}
      }
    }

    return map.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  Future<void> _runIf(
    String exec,
    List<String> args, {
    required void Function(String stdout) onSuccess,
  }) async {
    try {
      final res = await Process.run(exec, args)
          .timeout(const Duration(seconds: 30));
      if (res.exitCode == 0) {
        onSuccess(res.stdout.toString());
      }
    } catch (_) {}
  }
}
