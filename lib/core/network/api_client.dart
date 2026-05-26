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
    return _wrap(res);
  }

  Future<ApiEnvelope> getJson(String path) async {
    final res = await _dio.get<Map<String, dynamic>>(path);
    return _wrap(res);
  }

  /// 401/403 ni avtomatik sessionRevoked deb belgilash.
  ApiEnvelope _wrap(Response<Map<String, dynamic>> res) {
    final data = res.data;
    final isAuth = res.statusCode == 401 || res.statusCode == 403;
    if (data == null) {
      return ApiEnvelope(
        success: false,
        message: 'Empty body',
        sessionRevoked: isAuth,
        raw: null,
      );
    }
    final env = ApiEnvelope.fromJson(data);
    if (isAuth && !env.sessionRevoked) {
      return ApiEnvelope(
        success: false,
        message: env.message ?? 'Auth error',
        sessionRevoked: true,
        data: env.data,
        errors: env.errors,
        raw: data,
      );
    }
    return env;
  }

  Dio get dio => _dio;

  /// Raw binary upload (masalan, stream uchun JPEG frame).
  Options binaryOptions({required String agentKey, required int length}) {
    return Options(
      headers: {
        AppConfig.agentKeyHeader: agentKey,
        'Content-Type': 'application/octet-stream',
        'Content-Length': length.toString(),
      },
      sendTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 5),
      // Har qanday holatda ham response qaytarsin — call site o'zi qaror qiladi.
      // Bu yo'l bilan 4xx/5xx ni alohida log qila olamiz (silent fail emas).
      validateStatus: (code) => true,
    );
  }
}
