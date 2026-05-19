import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/providers/providers.dart';
import '../../../shared/widgets/app_logo.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<Map<String, String>>(
      future: _load(ref),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final m = snap.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const AppLogo(compact: true),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Dashboard',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _card(theme, 'Platforma', m['platform']!),
            _card(theme, 'Agent kaliti', m['key']!),
            _card(theme, 'Qurilma fingerprint', m['fp']!),
            _card(theme, 'Tarmoq', m['network']!),
            _card(theme, 'Oxirgi sync', m['lastSync']!),
            _card(theme, 'Keyingi sync (taxminan)', m['nextEta']!),
            _card(theme, 'Inventory yangilangan', m['inv']!),
            _card(theme, 'Oxirgi speed test', m['speed']!),
            _card(theme, 'Tray + startup', m['startup']!),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    await ref.read(agentSchedulerProvider).syncNow();
                    if (context.mounted) setState(() {});
                  },
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref
                        .read(speedTestRepositoryProvider)
                        .runAndReport(manual: true);
                    if (context.mounted) setState(() {});
                  },
                  icon: const Icon(Icons.speed),
                  label: const Text('Speed test'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    ref.read(agentSchedulerProvider).stop();
                    await ref.read(authRepositoryProvider).logoutLocal();
                    await ref.read(authSessionProvider.notifier).refresh();
                  },
                  child: const Text('Logout'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _card(ThemeData theme, String title, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(title, style: theme.textTheme.labelLarge),
        subtitle: Text(value, style: theme.textTheme.bodyLarge),
      ),
    );
  }

  Future<Map<String, String>> _load(WidgetRef ref) async {
    final auth = ref.read(authRepositoryProvider);
    final db = ref.read(appDatabaseProvider);
    final metrics = ref.read(systemMetricsProvider);
    final identity = ref.read(deviceIdentityProvider);
    final startup = ref.read(startupManagerProvider);

    final key = await auth.agentKey();
    final fp = await identity.machineGuidOrFingerprint();
    final row = await db.getAuthSessionRow();
    final intervalSec =
        int.tryParse(await db.getSetting('heartbeat_interval_sec') ?? '') ??
            300;
    final last = row['last_success_sync'] as String?;
    final inv = row['inventory_last_update'] as String?;
    final spd = row['speedtest_last_sent_at'] as String?;
    final lastDt = last != null ? DateTime.tryParse(last)?.toUtc() : null;
    final nextEta = lastDt?.add(Duration(seconds: intervalSec));
    final fmt = DateFormat.yMMMd().add_Hms();
    final net = await metrics.networkStatusLabel();
    bool startupOn = false;
    try {
      startupOn = await startup.isEnabled();
    } catch (_) {}

    String mask(String? s) {
      if (s == null || s.isEmpty) return '—';
      if (s.length <= 8) return s;
      return '${s.substring(0, 4)}…${s.substring(s.length - 4)}';
    }

    return {
      'platform': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'key': mask(key),
      'fp': mask(fp),
      'network': net,
      'lastSync': lastDt != null ? fmt.format(lastDt.toLocal()) : '—',
      'nextEta': nextEta != null ? fmt.format(nextEta.toLocal()) : '—',
      'inv': inv != null
          ? fmt.format(DateTime.parse(inv).toLocal())
          : '—',
      'speed': spd != null
          ? fmt.format(DateTime.parse(spd).toLocal())
          : '—',
      'startup': startupOn ? 'On' : 'Off',
    };
  }
}
