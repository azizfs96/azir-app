/// Environment configuration.
///
/// Override at build time:
///   flutter run --dart-define=WASLA_API_BASE=https://api.wasla.sa/api/v1
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
}
