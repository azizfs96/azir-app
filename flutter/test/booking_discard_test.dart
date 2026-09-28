import 'package:flutter_test/flutter_test.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// LEAVING A FILLED-IN FLOW MUST ASK FIRST
///
/// Backing out from the first step popped the route silently. Fine for an
/// untouched flow — but a customer who walked forward and came back to the
/// first step had a service, stylist, date and time on board, and one habitual
/// edge-swipe threw all of it away with nothing but a screen transition to
/// show for it.
///
/// The rule: an untouched flow leaves immediately; an answered one asks.
/// A service preselected by the storefront tile does not count as an answer —
/// the customer typed nothing to get it.
/// ============================================================================
void main() {
  testWidgets('an untouched flow leaves silently', (tester) async {
    final stores = FakeStoreRepository(
      storefront: storefrontFixture(staffSelection: false),
      slotsFor: (_) => [slot('12:00')],
    );

    final router = await pumpBookingFlow(tester, stores: stores);

    await systemBack(tester);

    expect(find.text('إلغاء الحجز؟'), findsNothing);
    expect(currentLocation(router), '/storefront');
  });

  testWidgets('a filled-in flow asks, and "keep" stays', (tester) async {
    final stores = FakeStoreRepository(
      storefront: storefrontFixture(staffSelection: false),
      slotsFor: (_) => [slot('12:00')],
    );

    final router = await pumpBookingFlow(tester, stores: stores);

    // Answer service + slot, then walk back to the first step.
    await tester.tap(find.text('Hair Cut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12:00'));
    await tester.pumpAndSettle();
    await systemBack(tester);
    await systemBack(tester);

    // Leaving now would cost the customer everything they chose.
    await systemBack(tester);

    expect(find.text('إلغاء الحجز؟'), findsOneWidget);

    await tester.tap(find.text('متابعة الحجز'));
    await tester.pumpAndSettle();

    expect(currentLocation(router), '/s/ABC12345/book',
        reason: '"Keep booking" left the flow anyway.');
    expect(find.text('Hair Cut'), findsOneWidget);
  });

  testWidgets('"discard" leaves', (tester) async {
    final stores = FakeStoreRepository(
      storefront: storefrontFixture(staffSelection: false),
      slotsFor: (_) => [slot('12:00')],
    );

    final router = await pumpBookingFlow(tester, stores: stores);

    await tester.tap(find.text('Hair Cut'));
    await tester.pumpAndSettle();
    await systemBack(tester);
    await systemBack(tester);

    await tester.tap(find.text('خروج'));
    await tester.pumpAndSettle();

    expect(currentLocation(router), '/storefront');
    expect(find.text('STOREFRONT_STUB'), findsOneWidget);
  });

  testWidgets('a preselected service alone does not trigger the prompt',
      (tester) async {
    final storefront = storefrontFixture(staffSelection: false);
    final stores = FakeStoreRepository(
      storefront: storefront,
      slotsFor: (_) => [slot('12:00')],
    );

    final router = await pumpBookingFlow(tester, stores: stores);

    // Back out of the plain entry, then re-enter FROM A SERVICE TILE.
    await systemBack(tester);
    router.push('/s/ABC12345/book', extra: storefront.services.first);
    await tester.pumpAndSettle();

    // Preselection skipped the service step — we are on date+time.
    expect(find.text('اختر الموعد'), findsOneWidget);

    // The customer answered nothing themselves; back must not interrogate.
    await systemBack(tester); // to the service step
    await systemBack(tester); // out

    expect(find.text('إلغاء الحجز؟'), findsNothing);
    expect(currentLocation(router), '/storefront');
  });
}
