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
      // To'g'ridan-to'g'ri Uint8List jo'natamiz — Stream.fromIterable Dio'da
      // ba'zan content-length mismatch sababli muvaffaqiyatsiz bo'ladi.
      final res = await api.dio.post<dynamic>(
        '/agent/stream/$sessionId/frame',
        data: jpeg,
        options: api.binaryOptions(agentKey: agentKey, length: jpeg.length),
      );
      if (res.statusCode == 410) {
        await stop(reason: 'session_ended');
        return;
      }
      if (res.statusCode == null || res.statusCode! < 200 || res.statusCode! >= 300) {
        _consecutiveFailures++;
        if (_framesSent < 3 || _consecutiveFailures % 5 == 0) {
          await logger.log(
            LogLevel.warn,
            'Frame HTTP ${res.statusCode}: ${res.data}',
            context: 'stream',
          );
        }
        if (_consecutiveFailures >= 20) {
          await stop(reason: 'http_errors');
        }
        return;
      }
      _framesSent++;
      _consecutiveFailures = 0;
      if (_framesSent <= 2 || _framesSent % 30 == 0) {
        await logger.log(
          LogLevel.info,
          'Frame #$_framesSent yuborildi (${jpeg.length} bayt, status ${res.statusCode})',
          context: 'stream',
        );
      }
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

  /// Linux'da screen capture — har xil desktop muhitlarida ishlaydigan
  /// usullarning to'liq zanjiri. Yutgan usul "qora bo'lmagan" rasm ishlab
  /// chiqaradi (kichik fayl hajmi qora rasm belgisi).
  String? _firstWorkingTool; // muvaffaqiyatli usulni cache qilamiz

  Future<String?> _captureLinux(String outPath) async {
    final env = Platform.environment;
    final isWayland = env['XDG_SESSION_TYPE'] == 'wayland' ||
        (env['WAYLAND_DISPLAY']?.isNotEmpty ?? false);
    final isGnome = (env['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase().contains('gnome') ||
        env['GNOME_DESKTOP_SESSION_ID']?.isNotEmpty == true;
    final isKde = (env['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase().contains('kde');

    // Avval cache'lagan usulni sinab ko'ramiz — har safar qaytadan probe qilmaymiz.
    if (_firstWorkingTool != null) {
      final ok = await _runCapture(_firstWorkingTool!, outPath, env);
      if (ok) return outPath;
      _firstWorkingTool = null; // qaytadan probe qilamiz
    }

    // Tartib: avval current DE/session uchun eng yaxshilari, keyin fallback'lar.
    final order = <String>[];
    if (isWayland && isGnome) {
      order.addAll(['gnome-dbus', 'gnome-screenshot', 'grim', 'ffmpeg-x11', 'scrot', 'import']);
    } else if (isWayland && isKde) {
      order.addAll(['kde-dbus', 'spectacle', 'grim', 'ffmpeg-x11', 'scrot']);
    } else if (isWayland) {
      order.addAll(['grim', 'gnome-screenshot', 'ffmpeg-x11', 'scrot']);
    } else {
      // X11 yoki noma'lum
      order.addAll(['scrot', 'import', 'ffmpeg-x11', 'gnome-screenshot', 'grim']);
    }

    for (final tool in order) {
      final ok = await _runCapture(tool, outPath, env);
      if (ok) {
        _firstWorkingTool = tool;
        await logger.log(LogLevel.info,
            'Linux capture: $tool yutdi', context: 'stream');
        return outPath;
      }
    }
    await logger.log(LogLevel.error,
        'Linux capture: hech bir usul ishlamadi (sinalgan: ${order.join(",")})',
        context: 'stream');
    return null;
  }

  Future<bool> _runCapture(String tool, String outPath, Map<String, String> env) async {
    // Eski faylni o'chirib qaytadan yaratamiz, aks holda eski rasm qoladi.
    try { File(outPath).deleteSync(); } catch (_) {}

    try {
      late ProcessResult res;
      switch (tool) {
        case 'gnome-dbus':
          // GNOME Shell o'z D-Bus orqali screenshot (Wayland'da ishlaydi, ruxsat shart emas).
          res = await Process.run('gdbus', [
            'call', '--session',
            '--dest', 'org.gnome.Shell.Screenshot',
            '--object-path', '/org/gnome/Shell/Screenshot',
            '--method', 'org.gnome.Shell.Screenshot.Screenshot',
            'true', 'false', outPath,
          ], environment: env);
          break;
        case 'kde-dbus':
          // KDE Plasma KWin screenshot
          res = await Process.run('gdbus', [
            'call', '--session',
            '--dest', 'org.kde.KWin.ScreenShot2',
            '--object-path', '/org/kde/KWin/ScreenShot2',
            '--method', 'org.kde.KWin.ScreenShot2.CaptureWorkspace',
            '{}', '0',
          ], environment: env);
          // KDE qaytaradi fd, oddiy fayl emas — pass o'tkazib yuboramiz hozircha.
          break;
        case 'scrot':
          res = await Process.run('scrot', ['-o', outPath], environment: env);
          break;
        case 'grim':
          res = await Process.run('grim', [outPath], environment: env);
          break;
        case 'gnome-screenshot':
          res = await Process.run('gnome-screenshot', ['-f', outPath], environment: env);
          break;
        case 'spectacle':
          res = await Process.run('spectacle', ['-b', '-n', '-o', outPath], environment: env);
          break;
        case 'import':
          res = await Process.run('import', ['-window', 'root', outPath], environment: env);
          break;
        case 'ffmpeg-x11':
          final display = env['DISPLAY'] ?? ':0';
          res = await Process.run('ffmpeg', [
            '-y', '-loglevel', 'error',
            '-f', 'x11grab',
            '-video_size', '1920x1080',
            '-i', display,
            '-frames:v', '1',
            outPath,
          ], environment: env);
          break;
        default:
          return false;
      }

      if (res.exitCode != 0) return false;
      final f = File(outPath);
      if (!f.existsSync()) return false;
      final size = f.lengthSync();
      // Qora rasm 6-10KB bo'ladi 1920x1080'da. Haqiqiy ekran kamida 30KB.
      if (size < 15000) {
        await logger.log(LogLevel.warn,
            '$tool yaratdi lekin juda kichik (${size} bayt) — qora rasm bo\'lishi mumkin',
            context: 'stream');
        return false;
      }
      return true;
    } catch (e) {
      // Komanda topilmadi yoki crash
      return false;
    }
  }
}
