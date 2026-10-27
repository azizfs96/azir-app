import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'token_store.dart';

/// Push registration for "new delivery assigned" / "order ready" pings.
///
/// Best-effort: push is an enhancement, so nothing here may block sign-in or
/// surface an error. Without a Firebase config file the calls simply fail
/// quietly and the driver still gets everything through the board's refresh.
class PushService {
  PushService(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  bool _wired = false;
  bool _tapsWired = false;

  Future<void> registerIfSignedIn() async {
    if (!await _tokens.hasToken()) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      if (Platform.isIOS) {
        var apns = await messaging.getAPNSToken();
        for (var i = 0; i < 12 && apns == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          apns = await messaging.getAPNSToken();
        }
      }

      final fcmToken = await messaging.getToken();
      if (fcmToken != null) await _send(fcmToken);

      if (!_wired) {
        _wired = true;
        messaging.onTokenRefresh.listen(_send);
      }
    } catch (_) {
      // See class docblock.
    }
  }

  /// A tapped notification opens its order (cold launch and warm resume).
  void wireOrderTaps(void Function(int orderId) openOrder) {
    if (_tapsWired) return;
    _tapsWired = true;

    try {
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        final id = _orderIdOf(message);
        if (id != null) openOrder(id);
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final id = _orderIdOf(message);
        if (id != null) openOrder(id);
      });
    } catch (_) {
      // Firebase not configured on this build.
    }
  }

  int? _orderIdOf(RemoteMessage? message) {
    final raw = message?.data['order_id'];
    if (raw == null) return null;
    return raw is int ? raw : int.tryParse(raw.toString());
  }

  Future<void> _send(String fcmToken) async {
    try {
      await _api.post(
        '/driver/device-tokens',
        body: {'token': fcmToken, 'platform': Platform.isIOS ? 'ios' : 'android'},
      );
    } catch (_) {
      // Swallowed on purpose.
    }
  }
}

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)),
);
