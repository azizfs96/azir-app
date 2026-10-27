/// Build-time configuration.
///
///   flutter build ios --dart-define=AZIR_API_BASE=https://api.azir.sa/api/v1
class Env {
  const Env._();

  static const apiBase = String.fromEnvironment(
    'AZIR_API_BASE',
    // Android emulators reach the host machine on 10.0.2.2, not localhost.
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );

  /// Sent as the map tiles' User-Agent, as OpenStreetMap's policy asks.
  static const packageName = 'sa.azir.driver';
}
