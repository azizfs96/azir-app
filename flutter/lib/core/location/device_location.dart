import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../localization/strings.dart';

/// Where the customer is right now — used to show "this branch is 2.3 km away"
/// and to sort branches nearest-first. Purely a convenience: every screen must
/// work when this is null (permission refused, web, no fix yet).
class DeviceLocation {
  const DeviceLocation(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// Straight-line distance to a point, in km. Null when the point has no pin.
  double? kmTo(double? lat, double? lng) {
    if (lat == null || lng == null) return null;
    return Geolocator.distanceBetween(latitude, longitude, lat, lng) / 1000;
  }
}

/// One permission prompt, one fix, cached for the session. The first read asks
/// for "when in use" permission; a refusal resolves to null quietly and is not
/// asked again until the app restarts (invalidate the provider to retry).
final deviceLocationProvider = FutureProvider<DeviceLocation?>((ref) async {
  if (kIsWeb) return null;
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }

    // A recent cached fix is good enough for a distance label and is instant.
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 5)) {
      return DeviceLocation(last.latitude, last.longitude);
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
    ).timeout(const Duration(seconds: 8));
    return DeviceLocation(pos.latitude, pos.longitude);
  } catch (_) {
    return null;
  }
});

/// "2.3 كم" / "850 م" — short enough to sit beside a branch name.
String formatDistance(Strings s, double km) {
  if (km < 1) return s.metersAway((km * 1000).round());
  return s.kmAway(km < 10 ? km.toStringAsFixed(1) : km.round().toString());
}
