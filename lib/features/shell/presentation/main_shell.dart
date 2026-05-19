import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/shell_tab_provider.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../../logs/presentation/logs_page.dart';
import '../../privacy/presentation/what_data_page.dart';
import '../../settings/presentation/settings_page.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const _titles = ['Dashboard', 'Settings', 'Logs', 'Ma’lumotlar'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellTabProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_titles[index])),
      body: IndexedStack(
        index: index,
        children: const [
          DashboardPage(),
          SettingsPage(),
          LogsPage(),
          WhatDataPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(shellTabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
          NavigationDestination(icon: Icon(Icons.article_outlined), selectedIcon: Icon(Icons.article), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.privacy_tip_outlined), selectedIcon: Icon(Icons.privacy_tip), label: 'Data'),
        ],
      ),
    );
  }
}
