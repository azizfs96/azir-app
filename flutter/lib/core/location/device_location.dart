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

/// A LIVE position: one permission prompt, then a stream that emits whenever
/// the customer has moved ~[_moveMeters] (so a distance label is never stale),
/// opening with the last known fix so the first frame already has a number.
/// Ends with null when permission is refused or location is off.
const _moveMeters = 30;

final deviceLocationProvider = StreamProvider<DeviceLocation?>((ref) async* {
  if (kIsWeb) {
    yield null;
    return;
  }

  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      yield null;
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      yield null;
      return;
    }

    // Something immediately, even if a little old — but only if it is recent:
    // a fix from hours ago would show yesterday's distance.
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp) < const Duration(minutes: 2)) {
      yield DeviceLocation(last.latitude, last.longitude);
    }

    // Then a fresh, accurate fix right now (the stream alone only reports
    // after the customer has MOVED, so a stationary customer would wait).
    try {
      final now = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      ).timeout(const Duration(seconds: 10));
      yield DeviceLocation(now.latitude, now.longitude);
    } catch (_) {
      // Fall through to the stream.
    }

    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: _moveMeters),
    ).map((p) => DeviceLocation(p.latitude, p.longitude)).handleError((_) {});
  } catch (_) {
    yield null;
  }
});

/// "2.3 كم" / "850 م" — short enough to sit beside a branch name.
String formatDistance(Strings s, double km) {
  if (km < 1) return s.metersAway((km * 1000).round());
  return s.kmAway(km < 10 ? km.toStringAsFixed(1) : km.round().toString());
}
