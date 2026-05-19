import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/providers/providers.dart';

class LogsPage extends ConsumerWidget {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: ref.read(appDatabaseProvider).recentLogs(limit: 300),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) {
          return const Center(child: Text('Hozircha yozuvlar yo‘q.'));
        }
        final fmt = DateFormat.yMMMd().add_Hms();
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final r = rows[i];
            final ts = r['created_at'] as String?;
            final dt = ts != null ? DateTime.tryParse(ts)?.toLocal() : null;
            return ListTile(
              dense: true,
              title: Text(r['message']?.toString() ?? ''),
              subtitle: Text('${r['level'] ?? ''}  ${dt != null ? fmt.format(dt) : ''}'),
            );
          },
        );
      },
    );
  }
}
