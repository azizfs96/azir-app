import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

/// Bookings (spec §18, §21, §22).
class BookingRepository {
  const BookingRepository(this._api);

  final ApiClient _api;

  Future<BookingResult> create(Map<String, dynamic> payload) async {
    final json = await _api.post('/bookings', body: payload);
    return BookingResult.fromJson(json);
  }

  Future<List<BookingResult>> list({String filter = 'upcoming'}) async {
    final json = await _api.get('/bookings', query: {'filter': filter});
    return ((json['data'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BookingResult.fromJson)
        .toList();
  }

  Future<void> cancel(int id, {String? reason}) =>
      _api.post('/bookings/$id/cancel', body: {'reason': ?reason});
}

class BookingResult {
  const BookingResult({
    required this.id,
    required this.reference,
    required this.status,
    required this.startsAt,
    required this.price,
    required this.currency,
    this.storeName,
    this.storeToken,
    this.serviceName,
    this.staffName,
    this.branchName,
    this.canCancel = false,
    this.canReschedule = false,
  });

  factory BookingResult.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? sub(String key) => json[key] as Map<String, dynamic>?;

    return BookingResult(
      id: json['id'] as int,
      reference: json['reference'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      startsAt: json['starts_at'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'SAR',
      storeName: sub('store')?['name'] as String?,
      storeToken: sub('store')?['token'] as String?,
      serviceName: sub('service')?['name'] as String?,
      staffName: sub('staff')?['name'] as String?,
      branchName: sub('branch')?['name'] as String?,
      canCancel: json['can_cancel'] as bool? ?? false,
      canReschedule: json['can_reschedule'] as bool? ?? false,
    );
  }

  final int id;
  final String reference;
  final String status;
  final String startsAt;
  final double price;
  final String currency;
  final String? storeName;
  final String? storeToken;
  final String? serviceName;
  final String? staffName;
  final String? branchName;

  /// Computed server-side so the app never re-implements cancellation policy.
  final bool canCancel;
  final bool canReschedule;
}

final bookingRepositoryProvider =
    Provider<BookingRepository>((ref) => BookingRepository(ref.watch(apiClientProvider)));

final myBookingsProvider = FutureProvider.family<List<BookingResult>, String>(
  (ref, filter) => ref.watch(bookingRepositoryProvider).list(filter: filter),
);
