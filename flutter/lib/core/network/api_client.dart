import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';
import '../storage/token_store.dart';

/// The single HTTP client (ARCHITECTURE.md §7).
///
/// Every API error carries a stable `error_code`; the app switches on that,
/// never on `message`, which is localized server-side.
class ApiClient {
  ApiClient(this._tokens, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: Env.apiBase)) {
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
          // An expired token should drop the session rather than leave the app
          // in a half-authenticated state.
          if (error.response?.statusCode == 401) {
            await _tokens.clear();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final TokenStore _tokens;

  Dio get dio => _dio;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final response = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    final response = await _dio.post<Map<String, dynamic>>(path, data: body);
    return response.data ?? const {};
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await _dio.delete<Map<String, dynamic>>(path);
    return response.data ?? const {};
  }
}

/// A failure the UI can act on.
class ApiFailure implements Exception {
  const ApiFailure(this.code, this.message, {this.fromServer = false});

  final String? code;

  /// NOT automatically safe to show. Only when [fromServer] is true has this
  /// been through the API's own localization; otherwise it is transport or
  /// exception text — "Instance of 'TypeError'", or a Dio timeout string in
  /// English inside an Arabic screen.
  final String message;

  /// Did the message come from the API's localized response body?
  ///
  /// The UI needs this to decide between showing [message] and showing its own
  /// localized fallback. Without it every caller had to choose between leaking
  /// exception text and discarding good server messages.
  final bool fromServer;

  static ApiFailure from(Object error) {
    if (error is DioException) {
      final data = error.response?.data;

      if (data is Map<String, dynamic>) {
        final code = data['error_code'] as String?;
        final message = data['message'] as String?;

        // Keep the code either way — SLOT_TAKEN still needs to be recognised
        // when the body carries no message.
        if (message != null && message.trim().isNotEmpty) {
          return ApiFailure(code, message, fromServer: true);
        }

        return ApiFailure(code, 'Request failed');
      }

      return ApiFailure(null, error.message ?? 'Network error');
    }

    return ApiFailure(null, error.toString());
  }

  /// Lost the race for a slot (§6.3) — the app should refresh availability.
  bool get isSlotTaken => code == 'SLOT_TAKEN';

  bool get isStoreNotFound => code == 'STORE_NOT_FOUND';

  @override
  String toString() => 'ApiFailure($code): $message';
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(tokenStoreProvider)),
);
