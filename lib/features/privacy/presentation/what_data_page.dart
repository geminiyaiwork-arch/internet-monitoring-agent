import 'package:flutter/material.dart';

import '../../../shared/widgets/app_logo.dart';

/// Transparency screen (TZ #26–30).
class WhatDataPage extends StatelessWidget {
  const WhatDataPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const AppLogo(height: 100),
        const SizedBox(height: 16),
        Text(
          'What data is collected',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'Internet Monitoring Agent yashirin ishlamaydi. Faqat sizning roziligingiz va '
          'ushbu dastur orqali ko‘rsatilgan ma’lumotlar yig‘iladi.',
        ),
        const SizedBox(height: 16),
        _section(theme, 'Heartbeat (muntazam)', const [
          'user_id va server bergan key',
          'qurilma nomi, Windows foydalanuvchi nomi (tizim hisobi)',
          'OS nomi va versiyasi, dastur versiyasi',
          'mahalliy IP, (mavjud bo‘lsa) ommaviy IP',
          'tarmoq holati (online/offline)',
          'vaqt belgisi, ishlab turish vaqti (uptime)',
          'xotira va disk hajmi/faol foydalanish, taxminiy CPU bandligi',
        ]),
        _section(theme, 'Inventar (ixtiyoriy, alohida rozilik)', const [
          'O‘rnatilgan dasturlar: ko‘rinadigan nom, versiya, nashriyotchi, o‘rnatilgan sana',
          'O‘zgarishlar diff ko‘rinishida yuboriladi (yangi/o‘chirilgan)',
        ]),
        const SizedBox(height: 16),
        Text(
          'Yig‘ilmaydi',
          style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        const Text(
          'Brauzer tarixi, parollar, xabar mazmuni, sayt kontenti, ilova bo‘yicha internet '
          'yo‘nalishlari monitoringi va boshqa nozik kontent — yig‘ilmaydi / yuborilmaydi.',
        ),
      ],
    );
  }

  Widget _section(ThemeData theme, String title, List<String> bullets) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...bullets.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(b)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
