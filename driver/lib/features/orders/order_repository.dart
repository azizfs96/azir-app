import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'order_model.dart';

/// The three boards the driver app shows.
enum BoardFilter {
  available('available'),
  mine('mine'),
  past('past');

  const BoardFilter(this.api);

  final String api;
}

class OrderRepository {
  OrderRepository(this._api);

  final ApiClient _api;

  Future<List<DriverOrder>> list(BoardFilter filter) async {
    final json = await _api.get('/driver/orders', query: {'filter': filter.api});
    return ((json['data'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DriverOrder.fromJson)
        .toList(growable: false);
  }

  Future<DriverOrder> show(int id) async => DriverOrder.fromJson(await _api.get('/driver/orders/$id'));

  /// First tap wins — the server locks the row; a loser gets ORDER_ALREADY_TAKEN.
  Future<DriverOrder> claim(int id) async =>
      DriverOrder.fromJson(await _api.post('/driver/orders/$id/claim'));

  /// `out_for_delivery` (picked up) or `completed` (handed over).
  Future<DriverOrder> updateStatus(int id, String status) async =>
      DriverOrder.fromJson(await _api.post('/driver/orders/$id/status', body: {'status': status}));

  Future<void> sendLocation({
    required double latitude,
    required double longitude,
    int? heading,
    double? speedKmh,
  }) => _api.post(
    '/driver/location',
    body: {'latitude': latitude, 'longitude': longitude, 'heading': ?heading, 'speed_kmh': ?speedKmh},
  );
}

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(ref.watch(apiClientProvider)),
);

/// A board list. Kept alive (not autoDispose) because the location heartbeat
/// watches "mine" to know whether a delivery is in progress.
final boardProvider = FutureProvider.family<List<DriverOrder>, BoardFilter>(
  (ref, filter) => ref.watch(orderRepositoryProvider).list(filter),
);

final orderProvider = FutureProvider.autoDispose.family<DriverOrder, int>(
  (ref, id) => ref.watch(orderRepositoryProvider).show(id),
);

/// True while one of MY orders is out for delivery — drives location sharing.
final hasActiveDeliveryProvider = Provider<bool>((ref) {
  final mine = ref.watch(boardProvider(BoardFilter.mine)).value;
  return mine?.any((o) => o.isOutForDelivery) ?? false;
});

/// Refresh every board and any open detail after a mutation.
void invalidateOrders(WidgetRef ref) {
  ref.invalidate(boardProvider);
  ref.invalidate(orderProvider);
}
