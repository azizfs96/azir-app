import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import 'address_repository.dart';
import 'delivery_selection.dart';
import 'fulfillment.dart';

/// What delivery to the chosen address costs — the SERVER's figure, computed
/// from the branch → address distance with the merchant's pricing (flat, per
/// km or tiers). Order placement runs the same code, so what the customer sees
/// here is exactly what they are charged, and an out-of-range address is known
/// before they tap "place order".
class DeliveryQuote {
  const DeliveryQuote({
    required this.allowed,
    required this.reason,
    required this.distanceKm,
    required this.fee,
    required this.mode,
    required this.maxDistanceKm,
    required this.minOrder,
  });

  final bool allowed;

  /// `OUT_OF_RANGE` or `NO_COORDINATES` when not allowed / unpriced.
  final String? reason;
  final double? distanceKm;
  final double fee;
  final String mode;
  final double? maxDistanceKm;
  final double minOrder;

  bool get isOutOfRange => !allowed && reason == 'OUT_OF_RANGE';

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) => DeliveryQuote(
        allowed: json['allowed'] as bool? ?? true,
        reason: json['reason'] as String?,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        fee: (json['fee'] as num?)?.toDouble() ?? 0,
        mode: json['mode'] as String? ?? 'fixed',
        maxDistanceKm: (json['max_distance_km'] as num?)?.toDouble(),
        minOrder: (json['min_order'] as num?)?.toDouble() ?? 0,
      );
}

typedef DeliveryQuoteKey = ({String token, int addressId, int? branchId});

final deliveryQuoteProvider = FutureProvider.autoDispose.family<DeliveryQuote, DeliveryQuoteKey>(
  (ref, key) async {
    final json = await ref.watch(apiClientProvider).get('/me/delivery-quote', query: {
      'store_token': key.token,
      'address_id': key.addressId,
      'branch_id': ?key.branchId,
    });
    return DeliveryQuote.fromJson(json);
  },
);

/// The quote the cart needs right now, or null when delivery is not the chosen
/// mode / no address exists yet. Derived from the same selections the checkout
/// uses, so the fee shown and the fee charged can never drift apart.
final cartQuoteKeyProvider = Provider.autoDispose.family<DeliveryQuoteKey?, String>((ref, token) {
  if (ref.watch(modeForStoreProvider(token)) != FulfillmentMode.delivery) return null;

  final addresses = ref.watch(addressesProvider).value ?? const [];
  if (addresses.isEmpty) return null;

  final selId = ref.watch(selectedAddressIdProvider);
  final address = addresses.any((a) => a.id == selId) ? selId! : addresses.first.id;
  return (token: token, addressId: address, branchId: ref.watch(selectedBranchIdProvider(token)));
});

/// The cart's live quote (null = not delivery / nothing to quote yet).
final cartDeliveryQuoteProvider = Provider.autoDispose.family<AsyncValue<DeliveryQuote>?, String>((ref, token) {
  final key = ref.watch(cartQuoteKeyProvider(token));
  return key == null ? null : ref.watch(deliveryQuoteProvider(key));
});
