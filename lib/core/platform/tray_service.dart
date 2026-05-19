import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:system_tray/system_tray.dart';

import '../config/app_config.dart';

enum TrayCommand {
  openDashboard,
  syncNow,
  toggleStartup,
  viewLogs,
  logout,
  exit,
}

typedef TrayCommandHandler = void Function(TrayCommand cmd);

/// System tray (Windows + macOS + Linux).
class TrayService {
  TrayService();

  final SystemTray _tray = SystemTray();
  final Menu _menu = Menu();
  bool _inited = false;

  Future<void> init({
    required ByteData logoAsset,
    required TrayCommandHandler onCommand,
    required bool startupEnabled,
  }) async {
    if (_inited) return;
    final dir = await getTemporaryDirectory();
    final iconFile = File('${dir.path}/ima_tray_logo.png');
    if (!await iconFile.exists()) {
      await iconFile.writeAsBytes(logoAsset.buffer.asUint8List());
    }
    await _tray.initSystemTray(
      iconPath: iconFile.path,
      toolTip: AppConfig.appName,
    );
    _tray.registerSystemTrayEventHandler((event) {
      if (event == kSystemTrayEventClick) {
        onCommand(TrayCommand.openDashboard);
      }
    });
    await _rebuildMenu(onCommand, startupEnabled);
    await _tray.setContextMenu(_menu);
    _inited = true;
  }

  Future<void> refreshStartupCheckbox(bool enabled, TrayCommandHandler onCommand) async {
    if (!_inited) return;
    await _rebuildMenu(onCommand, enabled);
    await _tray.setContextMenu(_menu);
  }

  Future<void> _rebuildMenu(TrayCommandHandler onCommand, bool startupEnabled) async {
    final items = <MenuItemBase>[
      MenuItemLabel(
        label: 'Open Dashboard',
        name: 'dash',
        onClicked: (_) => onCommand(TrayCommand.openDashboard),
      ),
      MenuItemLabel(
        label: 'Sync Now',
        name: 'sync',
        onClicked: (_) => onCommand(TrayCommand.syncNow),
      ),
      MenuItemCheckbox(
        label: 'Run on system startup',
        name: 'startup',
        checked: startupEnabled,
        onClicked: (_) => onCommand(TrayCommand.toggleStartup),
      ),
      MenuItemLabel(
        label: 'View Logs',
        name: 'logs',
        onClicked: (_) => onCommand(TrayCommand.viewLogs),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Logout',
        name: 'logout',
        onClicked: (_) => onCommand(TrayCommand.logout),
      ),
      MenuItemLabel(
        label: 'Exit',
        name: 'exit',
        onClicked: (_) => onCommand(TrayCommand.exit),
      ),
    ];
    await _menu.buildFrom(items);
  }

  Future<void> destroy() => _tray.destroy();
}
