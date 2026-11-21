import 'package:dio/dio.dart';
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
///
/// …or by DISCOVERY (test builds only): when the build carries
/// `WASLA_DISCOVERY_URL`, the app fetches that tiny text file — the current
/// public address of the developer's machine, republished by a watchdog every
/// time the temporary tunnel restarts — and switches to it when the compiled
/// address stops answering. Never set for production builds.
class Env {
  const Env._();

  static const apiBase = String.fromEnvironment(
    'WASLA_API_BASE',
    // Android emulators reach the host machine on 10.0.2.2, not localhost.
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  /// Where test builds look up the live API address (empty = disabled).
  static const discoveryUrl = String.fromEnvironment('WASLA_DISCOVERY_URL', defaultValue: '');

  static const webUrl = String.fromEnvironment(
    'WASLA_WEB_URL',
    defaultValue: 'https://wasla.sa',
  );

  /// The path segment in wasla.sa/s/8F72K
  static const storeLinkPath = 's';

  static const _overrideKey = 'wasla.api_base_override';
  static String? _override;

  /// A discovered address lives in memory only, so a later build that compiles
  /// in a real server is never shadowed by a stale tunnel from a previous run.
  static String? _discovered;
  static DateTime? _lastDiscovery;
  static Future<bool>? _inFlight;

  /// The API base in effect right now: discovered, else the saved override,
  /// else the build's.
  static String get current => _discovered ?? _override ?? apiBase;

  static String? get override => _override;

  /// Look up the live address (see class doc). Returns true when it switched
  /// to a new, answering address. Cheap to call often: throttled to once per
  /// 20 s and de-duplicated while a lookup is running.
  static Future<bool> discover({bool force = false}) {
    if (discoveryUrl.isEmpty) return Future.value(false);
    final running = _inFlight;
    if (running != null) return running;
    final last = _lastDiscovery;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(seconds: 20)) {
      return Future.value(false);
    }
    _lastDiscovery = DateTime.now();
    final f = _discoverNow().whenComplete(() => _inFlight = null);
    _inFlight = f;
    return f;
  }

  static Future<bool> _discoverNow() async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.plain,
    ));
    try {
      // Cache-buster: the file is served through a CDN that caches by full URL.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final sep = discoveryUrl.contains('?') ? '&' : '?';
      final res = await dio.get<String>('$discoveryUrl${sep}t=$stamp');
      final line = (res.data ?? '').trim().split('\n').first.trim().replaceFirst(RegExp(r'/+$'), '');
      if (!line.startsWith('https://') && !line.startsWith('http://')) return false;
      final candidate = line.endsWith('/api/v1') ? line : '$line/api/v1';
      if (candidate == current) return false;
      final health = await dio.get<String>(
        '$candidate/health',
        options: Options(validateStatus: (_) => true),
      );
      if (health.statusCode != 200) return false;
      _discovered = candidate;
      return true;
    } catch (_) {
      return false;
    } finally {
      dio.close();
    }
  }

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
