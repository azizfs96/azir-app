import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';
import 'token_store.dart';

/// The single HTTP client. Every API error carries a stable `error_code`; the
/// app switches on that, never on `message`, which is localized server-side.
class ApiClient {
  ApiClient(this._tokens, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(baseUrl: Env.apiBase)) {
    _dio.options
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 20)
      ..headers['Accept'] = 'application/json';

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokens.read();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          options.headers['Accept-Language'] = await _tokens.locale();
          handler.next(options);
        },
        onError: (error, handler) async {
          // A revoked token (the merchant deactivated this driver) drops the
          // session instead of leaving the app half signed-in.
          if (error.response?.statusCode == 401) {
            await _tokens.clear();
            onUnauthorized?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStore _tokens;

  /// Set by the session controller so a 401 anywhere signs the driver out.
  void Function()? onUnauthorized;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final response = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    final response = await _dio.post<Map<String, dynamic>>(path, data: body);
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> delete(String path, {Object? body}) async {
    final response = await _dio.delete<Map<String, dynamic>>(path, data: body);
    return response.data ?? const {};
  }
}

/// A failure the UI can act on.
class ApiFailure implements Exception {
  const ApiFailure(this.code, this.message, {this.fromServer = false, this.statusCode});

  final String? code;

  /// Safe to show only when [fromServer] is true (localized by the API).
  final String message;
  final bool fromServer;
  final int? statusCode;

  static ApiFailure from(Object error) {
    if (error is ApiFailure) return error;
    if (error is DioException) {
      final data = error.response?.data;
      final status = error.response?.statusCode;
      if (data is Map<String, dynamic>) {
        final code = data['error_code'] as String?;
        final message = data['message'] as String?;
        if (message != null && message.trim().isNotEmpty) {
          return ApiFailure(code, message, fromServer: true, statusCode: status);
        }
        return ApiFailure(code, 'Request failed', statusCode: status);
      }
      return ApiFailure(null, error.message ?? 'Network error', statusCode: status);
    }
    return ApiFailure(null, error.toString());
  }

  bool get isUnauthorized => statusCode == 401;

  bool get isAlreadyTaken => code == 'ORDER_ALREADY_TAKEN';

  @override
  String toString() => 'ApiFailure($code): $message';
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(tokenStoreProvider)));
