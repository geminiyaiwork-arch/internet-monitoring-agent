import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';

import '../../../core/logging/app_logger.dart';
// LogLevel for log() calls (this file uses logger.log).
import '../../../core/network/api_client.dart';
import '../../../core/secure/secure_vault.dart';

/// MJPEG screen streaming xizmati.
/// Admin browser har 333ms da frame oladi; biz bir xil tempda ekranni rasmga olib
/// JPEG sifatida POST qilamiz: /api/v1/agent/stream/{session}/frame
class StreamService {
  StreamService({
    required this.api,
    required this.vault,
    required this.logger,
  });

  final ApiClient api;
  final SecureVault vault;
  final AppLogger logger;

  Timer? _ticker;
  int? _activeSessionId;
  bool _busy = false;
  int _consecutiveFailures = 0;
  int _framesSent = 0;

  bool get isStreaming => _activeSessionId != null;
  int? get currentSessionId => _activeSessionId;

  Future<void> start({
    required int sessionId,
    required int fps,
    required int jpegQuality,
  }) async {
    if (_activeSessionId == sessionId) return;
    if (_activeSessionId != null) {
      await stop(reason: 'restart');
    }
    _activeSessionId = sessionId;
    _consecutiveFailures = 0;
    _framesSent = 0;
    final intervalMs = (1000 / fps.clamp(1, 5)).round();
    await logger.log(
      LogLevel.info,
      'Stream boshlandi: session=$sessionId, fps=$fps, quality=$jpegQuality, interval=${intervalMs}ms',
      context: 'stream',
    );
    _ticker = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      _captureAndSend(jpegQuality);
    });
  }

  Future<void> stop({String reason = 'manual'}) async {
    _ticker?.cancel();
    _ticker = null;
    final id = _activeSessionId;
    _activeSessionId = null;
    if (id != null) {
      await logger.log(
        LogLevel.info,
        'Stream to\'xtatildi: session=$id, reason=$reason, frames=$_framesSent',
        context: 'stream',
      );
    }
  }

  Future<void> _captureAndSend(int quality) async {
    if (_busy) return;
    final sessionId = _activeSessionId;
    if (sessionId == null) return;
    _busy = true;
    try {
      final jpeg = await _grabJpeg(quality);
      if (jpeg == null) {
        _consecutiveFailures++;
        if (_consecutiveFailures >= 10) {
          await logger.log(
            LogLevel.error,
            'Stream: 10 ta ketma-ket capture xato — to\'xtatilmoqda',
            context: 'stream',
          );
          await stop(reason: 'capture_failed');
        }
        return;
      }
      final agentKey = await vault.readAgentKey();
      if (agentKey == null) {
        await stop(reason: 'no_key');
        return;
      }
      // baseUrl allaqachon /api/v1 bilan tugaydi, shu sababli path /v1 prefix'siz.
      final res = await api.dio.post<dynamic>(
        '/agent/stream/$sessionId/frame',
        data: Stream.fromIterable([jpeg]),
        options: api.binaryOptions(agentKey: agentKey, length: jpeg.length),
      );
      if (res.statusCode == 410) {
        await stop(reason: 'session_ended');
        return;
      }
      _framesSent++;
      _consecutiveFailures = 0;
    } catch (e) {
      _consecutiveFailures++;
      if (_consecutiveFailures % 5 == 0) {
        await logger.log(
          LogLevel.warn,
          'Stream frame yuborilmadi (#$_consecutiveFailures): $e',
          context: 'stream',
        );
      }
      if (_consecutiveFailures >= 20) {
        await stop(reason: 'too_many_failures');
      }
    } finally {
      _busy = false;
    }
  }

  Future<Uint8List?> _grabJpeg(int quality) async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final path =
          '${tmpDir.path}/ima_stream_${DateTime.now().microsecondsSinceEpoch}.png';

      // Linux: bevosita scrot/grim/gnome-screenshot orqali (screen_capturer
      // paketi Wayland'da va ba'zi distrolarda ishonchsiz). Windows/macOS uchun
      // screen_capturer ishlatamiz.
      String? finalPath;
      if (Platform.isLinux) {
        finalPath = await _captureLinux(path);
      } else {
        final shot = await ScreenCapturer.instance.capture(
          mode: CaptureMode.screen,
          imagePath: path,
          silent: true,
          copyToClipboard: false,
        );
        finalPath = shot?.imagePath;
      }

      if (finalPath == null) {
        await logger.log(LogLevel.error,
            'Screen capture returned null path', context: 'stream');
        return null;
      }
      final file = File(finalPath);
      if (!file.existsSync()) {
        await logger.log(LogLevel.error,
            'Captured file does not exist: $finalPath', context: 'stream');
        return null;
      }
      final png = file.readAsBytesSync();
      try {
        file.deleteSync();
      } catch (_) {}

      if (png.length < 100) {
        await logger.log(LogLevel.error,
            'Captured file too small: ${png.length} bytes', context: 'stream');
        return null;
      }

      // PNG/JPEG ni decode qilish (scrot ba'zan jpeg ham qaytaradi).
      final decoded = img.decodeImage(png);
      if (decoded == null) {
        await logger.log(LogLevel.error,
            'Image decode returned null (${png.length} bytes)',
            context: 'stream');
        return null;
      }
      final resized = decoded.width > 1280
          ? img.copyResize(decoded, width: 1280)
          : decoded;
      return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    } catch (e, st) {
      await logger.log(LogLevel.error,
          'Screen capture exception: $e\n$st', context: 'stream');
      return null;
    }
  }

  /// Linux'da bir nechta capture vositasini sinab ko'rish:
  /// scrot (X11) -> grim (Wayland) -> gnome-screenshot -> import (imagemagick).
  Future<String?> _captureLinux(String outPath) async {
    // X11/Wayland session aniqlash.
    final isWayland = Platform.environment['XDG_SESSION_TYPE'] == 'wayland' ||
        Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty == true;

    // Tartib: Wayland bo'lsa grim birinchi, X11 bo'lsa scrot birinchi.
    final attempts = isWayland
        ? [
            ['grim', [outPath]],
            ['gnome-screenshot', ['-f', outPath]],
            ['scrot', ['-o', outPath]],
          ]
        : [
            ['scrot', ['-o', outPath]],
            ['import', ['-window', 'root', outPath]],
            ['gnome-screenshot', ['-f', outPath]],
            ['grim', [outPath]],
          ];

    for (final entry in attempts) {
      final cmd = entry[0] as String;
      final args = entry[1] as List<String>;
      try {
        final res = await Process.run(cmd, args,
            runInShell: false, environment: Platform.environment);
        if (res.exitCode == 0 && File(outPath).existsSync()) {
          return outPath;
        }
      } catch (_) {
        // Komanda topilmadi yoki ishlamadi — keyingisini sinaymiz.
      }
    }
    return null;
  }
}
