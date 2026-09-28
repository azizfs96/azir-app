import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'booking_repository.dart';

/// The customer's bookings AT ONE STORE (spec §5, §46).
///
/// Powers the "My bookings" tab on a storefront. Scoped by store_token so a
/// merchant's page shows only that merchant's history — the customer's other
/// merchants are none of this page's business.
class StoreBookings {
  const StoreBookings({required this.upcoming, required this.past});

  final List<BookingResult> upcoming;
  final List<BookingResult> past;

  bool get isEmpty => upcoming.isEmpty && past.isEmpty;
}

final storeBookingsProvider = FutureProvider.family<StoreBookings, String>((ref, token) async {
  final tokens = ref.watch(tokenStoreProvider);

  // Signed out means no history — the empty state, not an error.
  if (!await tokens.hasToken()) {
    return const StoreBookings(upcoming: [], past: []);
  }

  final api = ref.watch(apiClientProvider);

  Future<List<BookingResult>> fetch(String filter) async {
    final json = await api.get('/bookings', query: {
      'filter': filter,
      'store_token': token.toUpperCase(),
    });

    return ((json['data'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BookingResult.fromJson)
        .toList();
  }

  try {
    final results = await Future.wait([fetch('upcoming'), fetch('past')]);
    return StoreBookings(upcoming: results[0], past: results[1]);
  } on DioException catch (error) {
    if (error.response?.statusCode == 401) {
      return const StoreBookings(upcoming: [], past: []);
    }
    rethrow;
  }
});
