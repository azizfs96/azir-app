import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/storefront.dart';

/// Store resolution and availability (spec §6, §17, §31).
class StoreRepository {
  const StoreRepository(this._api);

  final ApiClient _api;

  /// THE QR RESOLUTION CALL. This is what a scan hits.
  Future<Storefront> resolve(String token) async {
    final json = await _api.get('/stores/${token.toUpperCase()}');
    return Storefront.fromJson(json);
  }

  /// Bookable start times for a day (spec §17).
  Future<List<Slot>> availability({
    required String storeToken,
    required int serviceId,
    required DateTime date,
    int? branchId,
    int? staffId,
  }) async {
    final json = await _api.get(
      '/stores/${storeToken.toUpperCase()}/availability',
      query: {
        'service_id': serviceId,
        'date': _ymd(date),
        'branch_id': ?branchId,
        'staff_id': ?staffId,
      },
    );

    final days = (json['days'] as List?) ?? const [];
    if (days.isEmpty) return const [];

    final slots = (days.first as Map<String, dynamic>)['slots'] as List? ?? const [];

    return slots
        .whereType<Map<String, dynamic>>()
        .map(Slot.fromJson)
        .toList();
  }

  static String _ymd(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// One bookable start time.
///
/// `staffId` is null when the merchant hides staff — the customer picks a TIME
/// and the backend decides who serves them (spec §9).
class Slot {
  const Slot({required this.startsAt, required this.time, this.staffId, this.staffName});

  factory Slot.fromJson(Map<String, dynamic> json) => Slot(
        startsAt: json['starts_at'] as String? ?? '',
        time: json['time'] as String? ?? '',
        staffId: json['staff_id'] as int?,
        staffName: json['staff_name'] as String?,
      );

  final String startsAt;
  final String time;
  final int? staffId;
  final String? staffName;
}

final storeRepositoryProvider =
    Provider<StoreRepository>((ref) => StoreRepository(ref.watch(apiClientProvider)));

/// A resolved storefront, cached per token for the session.
final storefrontProvider = FutureProvider.family<Storefront, String>(
  (ref, token) => ref.watch(storeRepositoryProvider).resolve(token),
);

/// Warm the storefront cache for the stores the customer can see.
///
/// Fired from the home screen the moment the store list arrives, so tapping a
/// card finds the payload already resolved instead of showing a spinner for a
/// full network round trip. Fire-and-forget: a failure here just means the
/// tap falls back to fetching normally.
void prefetchStorefronts(WidgetRef ref, Iterable<String> tokens) {
  for (final token in tokens.take(12)) {
    ref.read(storefrontProvider(token).future).ignore();
  }
}
