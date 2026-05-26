import 'package:flutter/material.dart';

/// Stream paytida foydalanuvchi ekranida har doim ko'rinadigan ogohlantirish.
/// Bu vidget asosiy oyna yopiq bo'lsa ham `flutter_overlay_window`-siz, oddiy
/// `MaterialBanner` ko'rinishida main shell'da chiqadi (ekran kuzatuvi haqida ETIK xabar).
class StreamNotificationBanner extends StatelessWidget {
  const StreamNotificationBanner({
    super.key,
    required this.adminName,
  });

  final String adminName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFDC2626),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const _PulsingDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Sizning ekraningiz hozir kuzatilmoqda',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Administrator: $adminName',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5 + 0.5 * _c.value),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.6 * _c.value),
              blurRadius: 8 * _c.value,
              spreadRadius: 2 * _c.value,
            ),
          ],
        ),
      ),
    );
  }
}
