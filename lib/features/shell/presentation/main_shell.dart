import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../shared/providers/providers.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  DateTime? _lastSync;
  Duration _remaining = Duration.zero;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Birinchi marta login bo'lganda hamma ma'lumotni darhol yuborish.
      try {
        await ref.read(agentSchedulerProvider).syncNow();
        if (mounted) setState(() => _lastSync = DateTime.now());
      } catch (_) {}
      // Har soniyada teskari sanoqni yangilash.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
      _updateRemaining();
      // 3 soniyadan keyin oynani treyga yashirish.
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) await windowManager.hide();
    });
  }

  void _updateRemaining() {
    if (!mounted) return;
    final scheduler = ref.read(agentSchedulerProvider);
    final next = scheduler.nextHeartbeatAt;
    final last = scheduler.lastHeartbeatAt;
    setState(() {
      if (next == null) {
        _remaining = scheduler.heartbeatInterval;
      } else {
        final diff = next.difference(DateTime.now().toUtc());
        _remaining = diff.isNegative ? Duration.zero : diff;
      }
      if (last != null) _lastSync = last.toLocal();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _resyncNow() async {
    try {
      await ref.read(agentSchedulerProvider).syncNow();
      _updateRemaining();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds % 60;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FB),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF22C55E), width: 3),
                  ),
                  child: const Icon(Icons.check_rounded, size: 80, color: Color(0xFF15803D)),
                ),
                const SizedBox(height: 26),
                Text(
                  'Ishlamoqda',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Monitoring agenti faollashtirildi.\nMa\'lumotlar har 10 daqiqada saytga uzatiladi.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                // Teskari sanoq dumaloq
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Keyingi yuborishgacha',
                        style: TextStyle(color: const Color(0xFF1E40AF), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_lastSync != null)
                  Text(
                    'Oxirgi sinxronizatsiya: ${_fmt(_lastSync!)}',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _resyncNow,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Hozir yuborish'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
