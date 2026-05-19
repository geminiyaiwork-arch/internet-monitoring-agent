import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../secure/secure_vault.dart';
import 'api_envelope.dart';
import 'mock_api_interceptor.dart';

/// Markaziy HTTP klient — har bir so'rovga X-Agent-Key headerni qo'shadi.
class ApiClient {
  ApiClient(this._vault) {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.instance.baseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 60),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final key = await _vault.readAgentKey();
          if (key != null && key.isNotEmpty) {
            options.headers[AppConfig.agentKeyHeader] = key;
          }
          handler.next(options);
        },
      ),
    );
    _dio.interceptors.add(MockApiInterceptor());
  }

  final SecureVault _vault;
  late final Dio _dio;

  void syncBaseUrl() {
    _dio.options.baseUrl = AppConfig.instance.baseUrl;
  }

  /// Bir martalik so'rov uchun headerga key qo'lda qo'yish (login paytida).
  Future<ApiEnvelope> postJson(
    String path,
    Map<String, dynamic> body, {
    String? overrideKey,
    Duration? timeout,
  }) async {
    final options = Options(
      headers: overrideKey == null
          ? null
          : {AppConfig.agentKeyHeader: overrideKey},
      sendTimeout: timeout,
      receiveTimeout: timeout,
    );
    final res = await _dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: options,
    );
    final data = res.data;
    if (data == null) {
      return ApiEnvelope(success: false, message: 'Empty body', raw: null);
    }
    return ApiEnvelope.fromJson(data);
  }

  Future<ApiEnvelope> getJson(String path) async {
    final res = await _dio.get<Map<String, dynamic>>(path);
    final data = res.data;
    if (data == null) {
      return ApiEnvelope(success: false, message: 'Empty body', raw: null);
    }
    return ApiEnvelope.fromJson(data);
  }

  Dio get dio => _dio;
}
