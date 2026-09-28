import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/token_store.dart';

/// ============================================================================
/// MY STORES — the whole discovery model (spec §5, §46)
///
/// There is no search, no nearby, no categories, and no endpoint that returns
/// stores the customer has not personally added. This repository has exactly
/// one read method, and that is deliberate.
/// ============================================================================
class MyStoresRepository {
  const MyStoresRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  Future<List<MyStore>> list() async {
    /*
     * A signed-out customer has no stores — that is the EMPTY state, not an
     * error. Opening the app for the first time is the most common case there
     * is, and showing "something went wrong" to a brand new user (instead of
     * "scan a QR code to add your first store") is the worst possible first
     * impression.
     *
     * Authentication is required to BOOK, not to open the app (spec §41).
     */
    if (!await _tokens.hasToken()) return const [];

    try {
      final json = await _api.get('/me/stores');
      return ((json['data'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MyStore.fromJson)
          .toList();
    } on DioException catch (error) {
      // An expired token is the same situation: no stores yet, not a failure.
      if (error.response?.statusCode == 401) return const [];
      rethrow;
    }
  }

  /// Called after a scan, and by the "enter store code" fallback (§8.3).
  Future<void> add(String token, {String via = 'qr'}) =>
      _api.post('/me/stores', body: {'token': token.toUpperCase(), 'added_via': via});

  Future<void> hide(String token) => _api.delete('/me/stores/$token');
}

class MyStore {
  const MyStore({
    required this.token,
    required this.name,
    this.description,
    this.logo,
    this.brandColor,
    this.nextAppointment,
    this.lastVisitAt,
  });

  factory MyStore.fromJson(Map<String, dynamic> json) => MyStore(
        token: json['token'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        logo: json['logo'] as String?,
        brandColor: json['brand_color'] as String?,
        nextAppointment: json['next_appointment'] is Map<String, dynamic>
            ? NextAppointment.fromJson(json['next_appointment'] as Map<String, dynamic>)
            : null,
        lastVisitAt: json['last_visit_at'] as String?,
      );

  final String token;
  final String name;
  final String? description;
  final String? logo;
  final String? brandColor;

  /// Decides which card variant the home screen shows (spec §5):
  /// "Next appointment / Tomorrow 7:00 PM" vs "Last visit / 5 days ago".
  final NextAppointment? nextAppointment;
  final String? lastVisitAt;
}

class NextAppointment {
  const NextAppointment({required this.id, required this.reference, required this.startsAt, this.service});

  factory NextAppointment.fromJson(Map<String, dynamic> json) => NextAppointment(
        id: json['id'] as int,
        reference: json['reference'] as String? ?? '',
        startsAt: json['starts_at'] as String? ?? '',
        service: json['service'] as String?,
      );

  final int id;
  final String reference;
  final String startsAt;
  final String? service;
}

final myStoresRepositoryProvider = Provider<MyStoresRepository>(
  (ref) => MyStoresRepository(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)),
);

final myStoresProvider = FutureProvider<List<MyStore>>(
  (ref) => ref.watch(myStoresRepositoryProvider).list(),
);
