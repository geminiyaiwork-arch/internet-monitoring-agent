import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Lokal mock (faqat sinov uchun). AppConfig.useMockApi=false bo'lsa o'chiq.
class MockApiInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!AppConfig.instance.useMockApi) {
      return super.onRequest(options, handler);
    }
    final path = options.uri.path;
    final now = DateTime.now().toUtc().toIso8601String();

    if (path.endsWith(AppConfig.loginPath)) {
      final headerKey =
          options.headers[AppConfig.agentKeyHeader]?.toString() ?? '';
      if (headerKey.isEmpty || headerKey == 'invalid') {
        handler.resolve(
          Response(
            requestOptions: options,
            data: {
              'success': false,
              'message': 'Invalid agent key (mock)',
              'server_time': now,
            },
          ),
        );
        return;
      }
      handler.resolve(
        Response(
          requestOptions: options,
          data: {
            'success': true,
            'message': 'Authorized (mock)',
            'data': {'device_id': headerKey.hashCode.abs()},
            'key': null,
            'server_time': now,
            'next_interval': 300,
          },
        ),
      );
      return;
    }

    if (path.endsWith(AppConfig.commandsPath)) {
      handler.resolve(
        Response(
          requestOptions: options,
          data: {
            'success': true,
            'message': 'OK',
            'data': {'commands': []},
            'server_time': now,
          },
        ),
      );
      return;
    }

    if (path.endsWith(AppConfig.speedTestPath)) {
      handler.resolve(
        Response(
          requestOptions: options,
          data: {
            'success': true,
            'message': 'Speed test received (mock)',
            'server_time': now,
            'next_interval': 1800,
          },
        ),
      );
      return;
    }

    handler.resolve(
      Response(
        requestOptions: options,
        data: {
          'success': true,
          'message': 'Received (mock)',
          'server_time': now,
          'next_interval': 300,
        },
      ),
    );
  }
}
