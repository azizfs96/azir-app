import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class DriverProfile {
  const DriverProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.vehicle,
    required this.isActive,
  });

  final int id;
  final String name;
  final String phone;
  final String? vehicle;
  final bool isActive;

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
    id: json['id'] as int,
    name: (json['name'] ?? '').toString(),
    phone: (json['phone'] ?? '').toString(),
    vehicle: json['vehicle'] as String?,
    isActive: json['is_active'] as bool? ?? true,
  );
}

class StoreInfo {
  const StoreInfo({required this.token, required this.name});

  final String? token;
  final String name;

  factory StoreInfo.fromJson(Map<String, dynamic> json) =>
      StoreInfo(token: json['token'] as String?, name: (json['name'] ?? '').toString());
}

class Session {
  const Session({required this.driver, required this.store});

  final DriverProfile driver;
  final StoreInfo store;

  Map<String, dynamic> toJson() => {
    'driver': {
      'id': driver.id,
      'name': driver.name,
      'phone': driver.phone,
      'vehicle': driver.vehicle,
      'is_active': driver.isActive,
    },
    'store': {'token': store.token, 'name': store.name},
  };

  static Session? tryParse(Map<String, dynamic>? json) {
    final driver = json?['driver'];
    final store = json?['store'];
    if (driver is! Map<String, dynamic> || store is! Map<String, dynamic>) return null;
    return Session(driver: DriverProfile.fromJson(driver), store: StoreInfo.fromJson(store));
  }
}

/// Who is signed in. `null` means the sign-in screen.
///
/// Startup is instant: a cached profile is shown while `/driver/me` refreshes
/// in the background, so a driver with a poor connection is never stuck on a
/// spinner. A 401 anywhere (the merchant deactivated the account) signs out.
class SessionController extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final tokens = ref.watch(tokenStoreProvider);
    ref.watch(apiClientProvider).onUnauthorized = () {
      if (state.value != null) state = const AsyncData(null);
    };

    if (!await tokens.hasToken()) return null;

    final cached = Session.tryParse(await tokens.profile());
    if (cached != null) {
      // Serve the cache now, refresh quietly.
      Future<void>.microtask(refresh);
      return cached;
    }
    return _fetchMe();
  }

  Future<Session?> _fetchMe() async {
    final json = await ref.read(apiClientProvider).get('/driver/me');
    final session = Session.tryParse(json);
    if (session != null) await ref.read(tokenStoreProvider).setProfile(session.toJson());
    return session;
  }

  Future<void> refresh() async {
    try {
      final session = await _fetchMe();
      if (session != null) state = AsyncData(session);
    } catch (e) {
      final failure = ApiFailure.from(e);
      if (failure.isUnauthorized || failure.statusCode == 403) {
        await ref.read(tokenStoreProvider).clear();
        state = const AsyncData(null);
      }
      // Any other failure keeps the cached session: the driver stays signed in.
    }
  }

  /// Throws [ApiFailure] on bad credentials / disabled account.
  Future<void> login(String phone, String password) async {
    final api = ref.read(apiClientProvider);
    final tokens = ref.read(tokenStoreProvider);

    final json = await api.post(
      '/auth/driver/login',
      body: {'phone': phone, 'password': password, 'device_name': 'driver-app'},
    );

    await tokens.write(json['token'] as String);
    final session = Session.tryParse(json) ?? await _fetchMe();
    if (session != null) await tokens.setProfile(session.toJson());
    state = AsyncData(session);
  }

  Future<void> logout() async {
    final api = ref.read(apiClientProvider);
    try {
      await api.post('/driver/logout');
    } catch (_) {
      // The local session goes regardless; the token also dies with deactivation.
    }
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, Session?>(SessionController.new);
