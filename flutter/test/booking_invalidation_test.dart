import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/features/booking/data/store_bookings_provider.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// BUG-4 — THE STOREFRONT'S BOOKING LIST MUST INCLUDE THE NEW BOOKING
///
/// On success the flow invalidated the HOME list but not the per-store one.
/// storeBookingsProvider is a family with no autoDispose, so its cached value
/// survives the whole session: the customer came back from the confirmation
/// screen to a list that did not contain the booking they had just made, and
/// only a manual pull-to-refresh fixed it.
/// ============================================================================
void main() {
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  Future<void> bookThrough(WidgetTester tester) async {
    await tester.tap(find.text('Hair Cut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12:00'));
    await tester.pumpAndSettle();
    // payment step -> confirm
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الحجز').last);
    await tester.pumpAndSettle();
  }

  testWidgets('a successful booking invalidates the store bookings list',
      (tester) async {
    var builds = 0;

    final stores = FakeStoreRepository(
      storefront: storefrontFixture(staffSelection: false),
      slotsFor: (_) => [slot('12:00')],
    );
    final bookings = FakeBookingRepository();

    await pumpBookingFlow(
      tester,
      stores: stores,
      bookings: bookings,
      onStoreBookingsBuild: () => builds++,
    );

    final container = containerOf(tester);

    // Prime the cache, exactly as visiting the storefront would.
    await container.read(storeBookingsProvider('ABC12345').future);
    expect(builds, 1);

    await bookThrough(tester);
    expect(bookings.createCalls, 1, reason: 'The booking was never submitted.');

    // Reading again must recompute, because the booking invalidated it.
    await container.read(storeBookingsProvider('ABC12345').future);

    expect(
      builds,
      2,
      reason: 'The storefront would still show a list without the new booking.',
    );
  });

  testWidgets('a FAILED booking does not invalidate the list', (tester) async {
    var builds = 0;

    final stores = FakeStoreRepository(
      storefront: storefrontFixture(staffSelection: false),
      slotsFor: (_) => [slot('12:00')],
    );
    final bookings = FakeBookingRepository(createError: Exception('boom'));

    await pumpBookingFlow(
      tester,
      stores: stores,
      bookings: bookings,
      onStoreBookingsBuild: () => builds++,
    );

    final container = containerOf(tester);
    await container.read(storeBookingsProvider('ABC12345').future);
    expect(builds, 1);

    await bookThrough(tester);

    await container.read(storeBookingsProvider('ABC12345').future);

    expect(
      builds,
      1,
      reason: 'A failed booking threw away a cache entry that was still correct.',
    );
  });
}
