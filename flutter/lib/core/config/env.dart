import 'package:shared_preferences/shared_preferences.dart';

/// Environment configuration.
///
/// Override at build time:
///   flutter run --dart-define=WASLA_API_BASE=https://api.azir.sa/api/v1
///
/// …or at RUN time: a server address saved on the device (hidden developer
/// setting — long-press "المساعدة" in the profile, or the sign-in title) wins
/// over the compiled default, so a tester can point the app at a tunnel or a
/// new server without a rebuild.
class Env {
  const Env._();

  static const apiBase = String.fromEnvironment(
    'WASLA_API_BASE',
    // Android emulators reach the host machine on 10.0.2.2, not localhost.
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  static const webUrl = String.fromEnvironment(
    'WASLA_WEB_URL',
    defaultValue: 'https://wasla.sa',
  );

  /// The path segment in wasla.sa/s/8F72K
  static const storeLinkPath = 's';

  static const _overrideKey = 'wasla.api_base_override';
  static String? _override;

  /// The API base in effect right now (runtime override, else the build's).
  static String get current => _override ?? apiBase;

  static String? get override => _override;

  /// Read the saved override before the first request (called from main()).
  static Future<void> loadOverride() async {
    try {
      _override = (await SharedPreferences.getInstance()).getString(_overrideKey);
    } catch (_) {
      _override = null;
    }
  }

  /// Save (or clear with null) the runtime API base. Takes effect on the next
  /// request — the HTTP client reads [current] per call.
  static Future<void> setOverride(String? base) async {
    final cleaned = base?.trim().replaceFirst(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    if (cleaned == null || cleaned.isEmpty) {
      _override = null;
      await prefs.remove(_overrideKey);
    } else {
      _override = cleaned.endsWith('/api/v1') ? cleaned : '$cleaned/api/v1';
      await prefs.setString(_overrideKey, _override!);
    }
  }
}
