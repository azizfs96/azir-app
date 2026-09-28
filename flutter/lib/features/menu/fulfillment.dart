import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/strings.dart';
import '../stores/domain/storefront.dart';

/// How the customer takes their order (Jahez's top pills). The enabled set comes
/// from the merchant's configuration, and the server re-validates the choice.
enum FulfillmentMode { pickup, dineIn, delivery, curbside }

extension FulfillmentModeX on FulfillmentMode {
  /// The wire value the orders API expects.
  String get api => switch (this) {
        FulfillmentMode.pickup => 'pickup',
        FulfillmentMode.dineIn => 'dine_in',
        FulfillmentMode.delivery => 'delivery',
        FulfillmentMode.curbside => 'curbside',
      };

  String label(Strings s) => switch (this) {
        FulfillmentMode.pickup => s.fulfillmentPickup,
        FulfillmentMode.dineIn => s.fulfillmentDineIn,
        FulfillmentMode.delivery => s.fulfillmentDelivery,
        FulfillmentMode.curbside => s.fulfillmentCurbside,
      };

  IconData get icon => switch (this) {
        FulfillmentMode.pickup => Icons.shopping_bag_outlined,
        FulfillmentMode.dineIn => Icons.restaurant_rounded,
        FulfillmentMode.delivery => Icons.delivery_dining_rounded,
        FulfillmentMode.curbside => Icons.directions_car_rounded,
      };
}

/// The modes a store offers, in the reference's order — pickup first (it becomes
/// the default and sits on the right in RTL), then curbside, delivery, dine-in.
/// Filtered to what the merchant enabled.
List<FulfillmentMode> enabledModes(StoreConfiguration c) => [
      if (c.orderPickup) FulfillmentMode.pickup,
      if (c.orderCurbside) FulfillmentMode.curbside,
      if (c.orderDelivery) FulfillmentMode.delivery,
      if (c.orderDineIn) FulfillmentMode.dineIn,
    ];

/// The customer's chosen fulfilment mode, kept per store token so the cart and
/// the storefront header always agree. One Notifier holds every store's choice
/// (mirroring the cart), read per token with [modeForStoreProvider].
final fulfillmentModeProvider =
    NotifierProvider<FulfillmentModeController, Map<String, FulfillmentMode>>(
  FulfillmentModeController.new,
);

class FulfillmentModeController extends Notifier<Map<String, FulfillmentMode>> {
  @override
  Map<String, FulfillmentMode> build() => const {};

  void set(String token, FulfillmentMode mode) => state = {...state, token: mode};

  /// Pick a sensible default the first time we know what the store offers.
  void ensureDefault(String token, List<FulfillmentMode> modes) {
    if (!state.containsKey(token) && modes.isNotEmpty) {
      state = {...state, token: modes.first};
    }
  }
}

/// The chosen mode for one store (null until defaulted).
final modeForStoreProvider = Provider.family<FulfillmentMode?, String>(
  (ref, token) => ref.watch(fulfillmentModeProvider)[token],
);
