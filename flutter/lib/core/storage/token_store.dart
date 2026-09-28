import 'package:shared_preferences/shared_preferences.dart';

/// Session token and locale preference.
///
/// SharedPreferences is adequate for the MVP: the Sanctum token is scoped to
/// this device and revocable server-side. Moving to the Keychain/Keystore later
/// is a change to this class only.
class TokenStore {
  static const _tokenKey = 'wasla.token';
  static const _localeKey = 'wasla.locale';
  static const _pendingStoreKey = 'wasla.pending_store';

  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_tokenKey);

  Future<void> write(String token) async =>
      (await SharedPreferences.getInstance()).setString(_tokenKey, token);

  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_tokenKey);

  Future<bool> hasToken() async => (await read()) != null;

  Future<String> locale() async =>
      (await SharedPreferences.getInstance()).getString(_localeKey) ?? 'ar';

  Future<void> setLocale(String locale) async =>
      (await SharedPreferences.getInstance()).setString(_localeKey, locale);

  /// A store token captured before the customer signed in.
  ///
  /// The customer scans, browses, picks a time, and only THEN is asked to
  /// authenticate (spec §41). This survives that detour so they land back on
  /// the right merchant.
  Future<String?> pendingStore() async =>
      (await SharedPreferences.getInstance()).getString(_pendingStoreKey);

  Future<void> setPendingStore(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(_pendingStoreKey);
    } else {
      await prefs.setString(_pendingStoreKey, token);
    }
  }
}
