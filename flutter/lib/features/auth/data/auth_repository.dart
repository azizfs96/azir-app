import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/token_store.dart';

/// Customer authentication: phone + OTP (spec §34). No password anywhere.
class AuthRepository {
  const AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  /// Returns true when the API is running with the fixed development code, so
  /// the UI can show the hint instead of leaving testers guessing.
  Future<bool> requestCode(String phone) async {
    final json = await _api.post('/auth/otp/request', body: {'phone': phone});
    return json['development_mode'] as bool? ?? false;
  }

  Future<void> verify({required String phone, required String code, String? firstName}) async {
    final json = await _api.post('/auth/otp/verify', body: {
      'phone': phone,
      'code': code,
      if (firstName != null && firstName.isNotEmpty) 'first_name': firstName,
    });

    final token = json['token'] as String?;
    if (token != null) await _tokens.write(token);
  }

  Future<bool> isSignedIn() => _tokens.hasToken();

  Future<void> signOut() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Clear locally regardless — a failed logout must not strand the user.
    }
    await _tokens.clear();
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)),
);

final isSignedInProvider = FutureProvider<bool>(
  (ref) => ref.watch(authRepositoryProvider).isSignedIn(),
);
