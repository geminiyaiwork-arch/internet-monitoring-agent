import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class SpeedTestResult {
  SpeedTestResult({
    required this.downloadMbps,
    required this.uploadMbps,
    required this.latencyMs,
    required this.testedAt,
    this.serverHost,
    this.bytesDown = 0,
    this.bytesUp = 0,
    this.error,
  });

  final double downloadMbps;
  final double uploadMbps;
  final int latencyMs;
  final DateTime testedAt;
  final String? serverHost;
  final int bytesDown;
  final int bytesUp;
  final String? error;

  Map<String, dynamic> toJson() => {
        'download_mbps': double.parse(downloadMbps.toStringAsFixed(2)),
        'upload_mbps': double.parse(uploadMbps.toStringAsFixed(2)),
        'ping_ms': latencyMs,
        if (serverHost != null) 'server_name': serverHost,
        'tested_at': testedAt.toUtc().toIso8601String(),
      };
}

/// Server bergan endpointlardan foydalanib download/upload tezligini o'lchaydi.
///
/// Endpoint sxema (server tomonidan beriladi yoki defaultga tushadi):
///  - GET  {downloadUrl}?bytes=N      -> N bayt raw response
///  - POST {uploadUrl}                 -> body: N bayt
///  - GET  {latencyUrl}                -> 200 OK qaytarsa kifoya
class SpeedTestClient {
  SpeedTestClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
            ));

  final Dio _dio;

  Future<SpeedTestResult> run({
    required String downloadUrl,
    required String uploadUrl,
    String? latencyUrl,
    int downloadBytes = 5 * 1024 * 1024,
    int uploadBytes = 2 * 1024 * 1024,
  }) async {
    final startedAt = DateTime.now();
    int latencyMs = 0;
    String? error;
    int bytesDown = 0;
    int bytesUp = 0;
    double downMbps = 0;
    double upMbps = 0;

    // 1) Latency
    if (latencyUrl != null) {
      try {
        final t0 = DateTime.now();
        await _dio.get<dynamic>(latencyUrl).timeout(const Duration(seconds: 10));
        latencyMs = DateTime.now().difference(t0).inMilliseconds;
      } catch (e) {
        error = 'latency: $e';
      }
    }

    // 2) Download
    try {
      final t0 = DateTime.now();
      final res = await _dio.get<List<int>>(
        downloadUrl,
        queryParameters: {'bytes': downloadBytes},
        options: Options(responseType: ResponseType.bytes),
      );
      final dt = DateTime.now().difference(t0).inMilliseconds;
      bytesDown = res.data?.length ?? 0;
      if (dt > 0 && bytesDown > 0) {
        downMbps = (bytesDown * 8 / 1e6) / (dt / 1000.0);
      }
    } catch (e) {
      error = '${error == null ? '' : '$error; '}download: $e';
    }

    // 3) Upload
    try {
      final payload = _randomBytes(uploadBytes);
      final t0 = DateTime.now();
      await _dio.post<dynamic>(
        uploadUrl,
        data: Stream<List<int>>.fromIterable([payload]),
        options: Options(
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Length': '${payload.length}',
          },
        ),
      );
      final dt = DateTime.now().difference(t0).inMilliseconds;
      bytesUp = payload.length;
      if (dt > 0 && bytesUp > 0) {
        upMbps = (bytesUp * 8 / 1e6) / (dt / 1000.0);
      }
    } catch (e) {
      error = '${error == null ? '' : '$error; '}upload: $e';
    }

    Uri? uri;
    try {
      uri = Uri.parse(downloadUrl);
    } catch (_) {}

    return SpeedTestResult(
      downloadMbps: downMbps,
      uploadMbps: upMbps,
      latencyMs: latencyMs,
      testedAt: startedAt,
      serverHost: uri?.host,
      bytesDown: bytesDown,
      bytesUp: bytesUp,
      error: error,
    );
  }

  Uint8List _randomBytes(int n) {
    final rnd = Random();
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = rnd.nextInt(256);
    }
    return b;
  }
}
