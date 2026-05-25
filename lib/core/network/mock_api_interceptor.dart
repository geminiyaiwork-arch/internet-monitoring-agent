import 'package:dio/dio.dart';

/// PRODUCTION'DA HECH QACHON ISHLAMAYDI — har doim haqiqiy serverga ulanadi.
/// (Dev sinovi uchun mock'lar olib tashlandi.)
class MockApiInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.next(options);
  }
}
