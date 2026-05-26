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
      final res = await api.dio.post<dynamic>(
        '/v1/agent/stream/$sessionId/frame',
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
      final shot = await ScreenCapturer.instance.capture(
        mode: CaptureMode.screen,
        imagePath: path,
        silent: true,
        copyToClipboard: false,
      );
      if (shot == null || shot.imagePath == null) return null;
      final file = File(shot.imagePath!);
      if (!file.existsSync()) return null;
      final png = file.readAsBytesSync();
      try {
        file.deleteSync();
      } catch (_) {}
      // PNG'ni JPEG'ga aylantirish + sifatni pasaytirib trafikni kamaytirish.
      final decoded = img.decodePng(png);
      if (decoded == null) return null;
      // Maksimal kenglik 1280px — 4K monitorlardan kelganda 75% trafik tejaladi.
      final resized = decoded.width > 1280
          ? img.copyResize(decoded, width: 1280)
          : decoded;
      return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    } catch (e) {
      return null;
    }
  }
}
