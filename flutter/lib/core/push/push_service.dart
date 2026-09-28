import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import '../storage/token_store.dart';

/// Registers this device for push notifications (order updates, spec §23).
///
/// The flow: ask permission, get the FCM token, hand it to the backend, and
/// keep it fresh when Firebase rotates it. Everything here is best-effort —
/// push is an enhancement, so a failure to register must never block the app
/// or surface an error to the customer.
class PushService {
  PushService(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  bool _wired = false;
  bool _tapsWired = false;

  /// Called on app start and after sign-in. No-op unless the customer is signed
  /// in (a device token is only useful once it belongs to an account).
  Future<void> registerIfSignedIn() async {
    if (!await _tokens.hasToken()) return;

    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // Show the banner even when the app is in the foreground (iOS otherwise
      // suppresses it), so an order update is never silently missed.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // On iOS the FCM token only resolves once APNs has handed a token to the
      // app (AppDelegate calls registerForRemoteNotifications at launch). That
      // can lag a second or two behind permission, so wait for it.
      if (Platform.isIOS) {
        var apns = await messaging.getAPNSToken();
        for (var i = 0; i < 12 && apns == null; i++) {
          await Future.delayed(const Duration(seconds: 1));
          apns = await messaging.getAPNSToken();
        }
      }

      final fcmToken = await messaging.getToken();
      if (fcmToken != null) await _send(fcmToken);

      // Register once for rotations — Firebase issues a new token now and then.
      if (!_wired) {
        _wired = true;
        messaging.onTokenRefresh.listen(_send);
      }
    } catch (_) {
      // Best-effort: never let push registration break startup or sign-in.
    }
  }

  /// Route a tapped order-update notification to its tracking screen. Handles
  /// both a cold launch (the app was terminated) and a warm resume (it was in
  /// the background). Wired once.
  void wireOrderTaps(void Function(int orderId) openOrder) {
    if (_tapsWired) return;
    _tapsWired = true;

    // Cold start (app was terminated): the launch message. Navigate after the
    // router has settled its initial route, otherwise the push is dropped and
    // the app just shows home.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      final id = _orderIdOf(message);
      if (id != null) openOrder(id);
    });

    // Warm start (app was in the background).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final id = _orderIdOf(message);
      if (id != null) openOrder(id);
    });
  }

  int? _orderIdOf(RemoteMessage? message) {
    final raw = message?.data['order_id'];
    if (raw == null) return null;
    return raw is int ? raw : int.tryParse(raw.toString());
  }

  Future<void> _send(String fcmToken) async {
    try {
      await _api.post('/me/device-tokens', body: {
        'token': fcmToken,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (_) {
      // Swallowed on purpose (see class docblock).
    }
  }
}

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)),
);
