import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `true` when the device has NO network connection at all.
///
/// This reports the OS link state (a thin platform channel), not whether the API
/// is actually reachable — request-level failures are still handled per screen.
/// Together they cover both "you're offline" and "the load failed".
final isOfflineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool isOffline(List<ConnectivityResult> results) =>
      results.isEmpty || results.every((r) => r == ConnectivityResult.none);

  try {
    yield isOffline(await connectivity.checkConnectivity());
  } catch (_) {
    yield false; // never block the UI on a connectivity read
  }
  yield* connectivity.onConnectivityChanged.map(isOffline);
});
