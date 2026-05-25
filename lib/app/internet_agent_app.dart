import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/app_config.dart';
import '../core/platform/tray_service.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/shell/presentation/main_shell.dart';
import '../shared/providers/providers.dart';
import '../shared/providers/shell_tab_provider.dart';

class InternetAgentApp extends ConsumerStatefulWidget {
  const InternetAgentApp({super.key, required this.startHidden});

  final bool startHidden;

  @override
  ConsumerState<InternetAgentApp> createState() => _InternetAgentAppState();
}

class _InternetAgentAppState extends ConsumerState<InternetAgentApp>
    with WindowListener {
  bool _trayReady = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(authSessionProvider.notifier).refresh();
      final logged = ref.read(authSessionProvider) == true;
      if (logged) {
        ref.read(agentSchedulerProvider).start();
      }
      await _setupTray();
      if (widget.startHidden) {
        await windowManager.hide();
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    } else {
      await windowManager.close();
    }
  }

  Future<void> _handleTray(TrayCommand cmd) async {
    final tray = ref.read(trayServiceProvider);
    final startup = ref.read(startupManagerProvider);
    switch (cmd) {
      case TrayCommand.openDashboard:
        ref.read(shellTabProvider.notifier).state = 0;
        // Restore + show + focus (Linux WMs hide bo'lgan oynani show() bilan
        // qaytarmasligi mumkin, restore() majburlaydi).
        try { await windowManager.restore(); } catch (_) {}
        await windowManager.show();
        await windowManager.focus();
        await windowManager.setAlwaysOnTop(true);
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.setAlwaysOnTop(false);
        break;
      case TrayCommand.syncNow:
        await ref.read(agentSchedulerProvider).syncNow();
        break;
      case TrayCommand.toggleStartup:
        final cur = await startup.isEnabled();
        await startup.setEnabled(!cur);
        await tray.refreshStartupCheckbox(
            await startup.isEnabled(), _handleTray);
        break;
      case TrayCommand.viewLogs:
        ref.read(shellTabProvider.notifier).state = 2;
        await windowManager.show();
        await windowManager.focus();
        break;
      case TrayCommand.logout:
        ref.read(agentSchedulerProvider).stop();
        await ref.read(authRepositoryProvider).logoutLocal();
        await ref.read(authSessionProvider.notifier).refresh();
        break;
      case TrayCommand.exit:
        tray.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.close();
        exit(0);
    }
  }

  Future<void> _setupTray() async {
    if (_trayReady) return;
    final tray = ref.read(trayServiceProvider);
    final logo = await rootBundle.load('assets/branding/app_logo.png');
    final startup = ref.read(startupManagerProvider);
    try {
      await tray.init(
        logoAsset: logo,
        startupEnabled: await startup.isEnabled(),
        onCommand: _handleTray,
      );
      _trayReady = true;
    } catch (_) {
      // Tray Linux'da DE bo'lmasa ishlamasligi mumkin — ilova UI rejimida davom etadi.
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool?>(authSessionProvider, (prev, next) {
      if (next == true) {
        ref.read(agentSchedulerProvider).start();
      } else if (next == false) {
        ref.read(agentSchedulerProvider).stop();
      }
    });
    final auth = ref.watch(authSessionProvider);
    return MaterialApp(
      title: AppConfig.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
        useMaterial3: true,
      ),
      home: auth == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : auth
              ? const MainShell()
              : const LoginPage(),
    );
  }
}
