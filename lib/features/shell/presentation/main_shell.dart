import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/providers.dart';
import '../../stream/presentation/stream_notification.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  DateTime? _lastSync;
  Duration _remaining = const Duration(minutes: 10);
  Timer? _ticker;
  String _status = 'Yuborilmoqda...';
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    // Ticker DARHOL ishga tushadi (syncNow ni kutmasdan).
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Birinchi sync ni fonda yuborish.
      _runSync();
      // Oyna ochiq qoladi — foydalanuvchi o'zi yopadi (X tugmasi treyga yashiradi).
    });
  }

  Future<void> _runSync() async {
    if (_syncing) return;
    if (mounted) {
      setState(() {
        _syncing = true;
        _status = 'Yuborilmoqda...';
      });
    }
    try {
      // Heartbeat ni alohida chaqirib, javobni tekshiramiz.
      final env = await ref.read(heartbeatRepositoryProvider).sendHeartbeat();
      if (!env.success) {
        if (env.sessionRevoked) {
          if (mounted) {
            setState(() => _status = 'Xato: Kalit bekor qilingan, qayta kiriting');
          }
          // 2s ko'rsatib, login sahifaga qaytarish.
          await Future.delayed(const Duration(seconds: 2));
          await ref.read(authSessionProvider.notifier).refresh();
          return;
        }
        if (mounted) {
          final msg = env.message ?? 'Noma\'lum xato';
          setState(() => _status = 'Xato: ${msg.length > 80 ? msg.substring(0, 80) : msg}');
        }
        return;
      }
      // Heartbeat ishladi — qolganlarini fonda yuborish.
      ref.read(agentSchedulerProvider).syncNow();
      if (mounted) {
        setState(() {
          _lastSync = DateTime.now();
          _status = 'Muvaffaqiyatli yuborildi';
        });
      }
    } catch (e) {
      final msg = e.toString();
      if (mounted) {
        setState(() => _status = 'Xato: ${msg.length > 80 ? msg.substring(0, 80) : msg}');
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
      _updateRemaining();
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = _remaining.inMinutes;
    final s = _remaining.inSeconds % 60;
    final stream = ref.watch(streamUiProvider);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FB),
      body: Column(
        children: [
          if (stream.isActive)
            StreamNotificationBanner(adminName: stream.adminName ?? 'Administrator'),
          Expanded(
            child: Center(
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
                  child: _syncing
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(
                            color: Color(0xFF15803D), strokeWidth: 4,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 80, color: Color(0xFF15803D)),
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
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Keyingi yuborishgacha',
                        style: TextStyle(color: Color(0xFF1E40AF), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontSize: 36,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _status.startsWith('Xato') ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _status,
                    style: TextStyle(
                      color: _status.startsWith('Xato') ? const Color(0xFFB91C1C) : const Color(0xFF334155),
                      fontSize: 12,
                    ),
                  ),
                ),
                if (_lastSync != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Oxirgi sinxronizatsiya: ${_fmt(_lastSync!)}',
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _syncing ? null : _runSync,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Hozir yuborish'),
                ),
              ],
            ),
          ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}
