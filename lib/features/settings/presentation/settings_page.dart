import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/providers/providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _downUrl;
  late final TextEditingController _upUrl;
  late final TextEditingController _pingUrl;
  bool _mock = false;
  bool _consentInventory = false;
  bool _consentProcesses = false;
  bool _startup = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController();
    _downUrl = TextEditingController();
    _upUrl = TextEditingController();
    _pingUrl = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final su = ref.read(startupManagerProvider);
    _baseUrl.text = await db.getSetting('base_url') ?? AppConfig.instance.baseUrl;
    _downUrl.text = await db.getSetting('speedtest_download_url') ?? '';
    _upUrl.text = await db.getSetting('speedtest_upload_url') ?? '';
    _pingUrl.text = await db.getSetting('speedtest_latency_url') ?? '';
    _mock = (await db.getSetting('use_mock_api')) == 'true';
    _consentInventory = await db.getSetting('consent_inventory') == 'true';
    _consentProcesses = await db.getSetting('consent_processes') == 'true';
    try {
      _startup = await su.isEnabled();
    } catch (_) {
      _startup = false;
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _downUrl.dispose();
    _upUrl.dispose();
    _pingUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final db = ref.read(appDatabaseProvider);
    final su = ref.read(startupManagerProvider);
    final url = _baseUrl.text.trim();
    if (url.isEmpty) return;
    await db.setSetting('base_url', url);
    await db.setSetting('use_mock_api', _mock.toString());
    await db.setSetting('consent_inventory', _consentInventory.toString());
    await db.setSetting('consent_processes', _consentProcesses.toString());
    if (_downUrl.text.trim().isNotEmpty) {
      await db.setSetting('speedtest_download_url', _downUrl.text.trim());
    }
    if (_upUrl.text.trim().isNotEmpty) {
      await db.setSetting('speedtest_upload_url', _upUrl.text.trim());
    }
    if (_pingUrl.text.trim().isNotEmpty) {
      await db.setSetting('speedtest_latency_url', _pingUrl.text.trim());
    }
    AppConfig.instance.baseUrl = url;
    AppConfig.instance.useMockApi = _mock;
    try {
      await su.setEnabled(_startup);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sozlamalar saqlandi')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Settings',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        TextField(
          controller: _baseUrl,
          decoration: const InputDecoration(
            labelText: 'API base URL',
            helperText: 'Masalan: https://e-mmtb.uz/api/v1',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        Text('Speed test endpointlari (admin sozlasa)',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _downUrl,
          decoration: const InputDecoration(
            labelText: 'Download URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _upUrl,
          decoration: const InputDecoration(
            labelText: 'Upload URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pingUrl,
          decoration: const InputDecoration(
            labelText: 'Latency / Ping URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        const Divider(),
        SwitchListTile(
          title: const Text('Mock API (tarmoqsiz sinov)'),
          subtitle:
              const Text("O'chirilsa, haqiqiy HTTPS so'rovlari yuboriladi."),
          value: _mock,
          onChanged: (v) => setState(() => _mock = v),
        ),
        SwitchListTile(
          title: const Text("O'rnatilgan dasturlar ro'yxati (rozilik)"),
          subtitle: const Text('Faqat dastur nomi/nashriyotchi/yuklash sanasi.'),
          value: _consentInventory,
          onChanged: (v) => setState(() => _consentInventory = v),
        ),
        SwitchListTile(
          title: const Text('Ishlayotgan jarayonlar (rozilik)'),
          subtitle: const Text('Process nomi, PID, RAM, CPU% — kontent yo\'q.'),
          value: _consentProcesses,
          onChanged: (v) => setState(() => _consentProcesses = v),
        ),
        SwitchListTile(
          title: const Text('Run on system startup'),
          subtitle: const Text(
              'Tray rejimida ishga tushadi (--startup-tray).'),
          value: _startup,
          onChanged: (v) => setState(() => _startup = v),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _save, child: const Text('Saqlash')),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(inventoryRepositoryProvider).sync(manual: true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Inventory yangilandi')));
                }
              },
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Refresh inventory'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(processesRepositoryProvider).sync(manual: true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Process snapshot yuborildi')));
                }
              },
              icon: const Icon(Icons.memory_outlined),
              label: const Text('Snapshot processes'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final env =
                    await ref.read(speedTestRepositoryProvider).runAndReport(
                          manual: true,
                        );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(env.success
                          ? 'Speed test bajarildi'
                          : 'Xato: ${env.message}')));
                }
              },
              icon: const Icon(Icons.speed),
              label: const Text('Run speed test'),
            ),
          ],
        ),
      ],
    );
  }
}
