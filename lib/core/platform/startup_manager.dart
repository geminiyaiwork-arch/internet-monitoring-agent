import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

/// Auto-start (Run on system startup) — uchchala platforma uchun bitta interfeys.
abstract class StartupManager {
  Future<bool> isEnabled();
  Future<void> setEnabled(bool value);
}

class DesktopStartupManager implements StartupManager {
  DesktopStartupManager() {
    LaunchAtStartup.instance.setup(
      appName: _appName,
      appPath: Platform.resolvedExecutable,
      args: const ['--startup-tray'],
      // packageName majburiy emas, launch_at_startup ichida default yetadi.
    );
  }

  static const _appName = 'InternetMonitoringAgent';

  @override
  Future<bool> isEnabled() => LaunchAtStartup.instance.isEnabled();

  @override
  Future<void> setEnabled(bool value) async {
    if (value) {
      await LaunchAtStartup.instance.enable();
    } else {
      await LaunchAtStartup.instance.disable();
    }
  }
}

/// Backwards-compatible alias.
typedef WindowsStartupManager = DesktopStartupManager;
