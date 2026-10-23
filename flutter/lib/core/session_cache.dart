import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/home/data/my_stores_repository.dart';
import '../features/menu/address_repository.dart';
import '../features/menu/car_repository.dart';
import '../features/menu/notifications_screen.dart';
import '../features/menu/order_repository.dart';
import '../features/menu/profile_screen.dart';

/// The order-related caches that go stale the moment an order is placed or
/// cancelled: both order lists and the home screen's "reorder your last order"
/// shortcut. None of these providers auto-dispose, so without this a new order
/// is missing from "my orders" until the app restarts.
void invalidateOrderCaches(WidgetRef ref) {
  ref.invalidate(myOrdersProvider('active'));
  ref.invalidate(myOrdersProvider('past'));
  ref.invalidate(lastReorderableOrderProvider);
}

/// Everything that belongs to the signed-in person. Called on sign-out and on
/// a fresh sign-in, so a second account on the same phone never sees the first
/// account's stores, orders, addresses, cars, inbox or name — and so providers
/// that errored with 401 while browsing as a guest are retried.
void invalidateUserCaches(WidgetRef ref) {
  ref.invalidate(isSignedInProvider);
  invalidateOrderCaches(ref);
  ref.invalidate(myStoresProvider);
  ref.invalidate(addressesProvider);
  ref.invalidate(carsProvider);
  ref.invalidate(notificationsProvider);
  ref.invalidate(meProvider);
}
