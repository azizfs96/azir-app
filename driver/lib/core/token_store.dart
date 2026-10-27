import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The driver's session token, locale, and a cached copy of the profile so the
/// app can open instantly (and offline) before `/driver/me` answers.
///
/// Keys are prefixed `azir_driver.` so nothing collides should this app ever
/// share a process (or a test) with the customer app.
class TokenStore {
  static const _tokenKey = 'azir_driver.token';
  static const _localeKey = 'azir_driver.locale';
  static const _profileKey = 'azir_driver.profile';

  Future<String?> read() async => (await SharedPreferences.getInstance()).getString(_tokenKey);

  Future<void> write(String token) async =>
      (await SharedPreferences.getInstance()).setString(_tokenKey, token);

  Future<bool> hasToken() async => (await read()) != null;

  Future<String> locale() async => (await SharedPreferences.getInstance()).getString(_localeKey) ?? 'ar';

  Future<void> setLocale(String locale) async =>
      (await SharedPreferences.getInstance()).setString(_localeKey, locale);

  Future<Map<String, dynamic>?> profile() async {
    final raw = (await SharedPreferences.getInstance()).getString(_profileKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setProfile(Map<String, dynamic> json) async =>
      (await SharedPreferences.getInstance()).setString(_profileKey, jsonEncode(json));

  /// Sign-out: token and cached profile go together.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_profileKey);
  }
}
