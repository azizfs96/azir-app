import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../orders/order_repository.dart';

enum HeartbeatStatus { idle, sharing, permissionDenied, serviceDisabled }

@immutable
class HeartbeatState {
  const HeartbeatState({this.status = HeartbeatStatus.idle, this.lastSentAt});

  final HeartbeatStatus status;
  final DateTime? lastSentAt;

  bool get isSharing => status == HeartbeatStatus.sharing;

  bool get needsAttention =>
      status == HeartbeatStatus.permissionDenied || status == HeartbeatStatus.serviceDisabled;

  HeartbeatState copyWith({HeartbeatStatus? status, DateTime? lastSentAt}) =>
      HeartbeatState(status: status ?? this.status, lastSentAt: lastSentAt ?? this.lastSentAt);
}

/// Shares the driver's position with the server ONLY while one of their orders
/// is out for delivery. Movement-driven (every ~25 m) with a floor of one post
/// per 5 s, plus a 60 s keep-alive when stationary so the customer's map never
/// shows a stale pin. Stops the moment the last delivery is handed over.
class LocationHeartbeat extends Notifier<HeartbeatState> {
  static const _minGap = Duration(seconds: 5);
  static const _keepAlive = Duration(seconds: 60);

  StreamSubscription<Position>? _stream;
  Timer? _keepAliveTimer;
  Position? _last;
  DateTime? _lastSent;
  bool _posting = false;

  @override
  HeartbeatState build() {
    ref.listen<bool>(
      hasActiveDeliveryProvider,
      (_, active) => active ? start() : stop(),
      fireImmediately: true,
    );
    ref.onDispose(stop);
    return const HeartbeatState();
  }

  Future<void> start() async {
    if (_stream != null) return;

    if (!await Geolocator.isLocationServiceEnabled()) {
      state = state.copyWith(status: HeartbeatStatus.serviceDisabled);
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      state = state.copyWith(status: HeartbeatStatus.permissionDenied);
      return;
    }

    _stream = Geolocator.getPositionStream(locationSettings: _settings())
        .listen(_onPosition, onError: (_) => stop());
    _keepAliveTimer = Timer.periodic(_keepAlive, (_) {
      final last = _last;
      if (last != null && (_lastSent == null || DateTime.now().difference(_lastSent!) >= _keepAlive)) {
        _post(last);
      }
    });
    state = state.copyWith(status: HeartbeatStatus.sharing);
  }

  void stop() {
    _stream?.cancel();
    _stream = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    if (state.status == HeartbeatStatus.sharing) state = const HeartbeatState();
  }

  /// Called from the board after the driver fixed permission in Settings.
  Future<void> retry() async {
    stop();
    if (ref.read(hasActiveDeliveryProvider)) await start();
  }

  void _onPosition(Position position) {
    _last = position;
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < _minGap) return;
    _post(position);
  }

  Future<void> _post(Position p) async {
    if (_posting) return;
    _posting = true;
    _lastSent = DateTime.now();
    try {
      await ref
          .read(orderRepositoryProvider)
          .sendLocation(
            latitude: p.latitude,
            longitude: p.longitude,
            heading: p.heading.isFinite && p.heading >= 0 ? p.heading.round() % 360 : null,
            speedKmh: p.speed.isFinite && p.speed >= 0
                ? double.parse((p.speed * 3.6).toStringAsFixed(1))
                : null,
          );
      state = state.copyWith(lastSentAt: _lastSent);
    } catch (_) {
      // A dropped heartbeat is retried by the next movement or keep-alive tick.
    } finally {
      _posting = false;
    }
  }

  LocationSettings _settings() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 25,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Easy App Driver',
          notificationText: 'مشاركة موقعك مع العميل أثناء التوصيل',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25);
  }
}

final heartbeatProvider = NotifierProvider<LocationHeartbeat, HeartbeatState>(LocationHeartbeat.new);
