import 'package:flutter_test/flutter_test.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// BUG-1 — THE SYSTEM BACK GESTURE MUST STEP, NOT EXIT
///
/// The booking flow is ONE route holding its step position in state, and only
/// the AppBar arrow was wired to step backwards. The iOS edge-swipe and the
/// Android hardware button go straight to the router, so they popped the whole
/// route and silently discarded every answer the customer had given.
///
/// On iPhone the edge-swipe is the dominant back affordance, so this was the
/// common path, not an edge case.
/// ============================================================================
void main() {
  Future<void> selectService(WidgetTester tester) async {
    await tester.tap(find.text('Hair Cut'));
    await tester.pumpAndSettle();
  }

  Future<void> selectAnyStaff(WidgetTester tester) async {
    // "Any available" is the first card on the staff step.
    await tester.tap(find.text('أي موظف متاح'));
    await tester.pumpAndSettle();
  }

  group('BUG-1 system back', () {
    testWidgets('steps back one step instead of leaving the flow', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [slot('12:00', staffId: 5, staffName: 'Sara')],
      );

      final router = await pumpBookingFlow(tester, stores: stores);

      await selectService(tester);
      await selectAnyStaff(tester);

      // We are now on the combined date+time screen.
      expect(find.text('اختر الموعد'), findsOneWidget);

      await systemBack(tester);

      // Must land on the staff step, still inside the booking route.
      expect(
        currentLocation(router),
        '/s/ABC12345/book',
        reason: 'The system back gesture left the booking flow entirely.',
      );
      expect(find.text('STOREFRONT_STUB'), findsNothing);
      expect(find.text('أي موظف متاح'), findsOneWidget);
    });

    testWidgets('preserves answers already given', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [slot('12:00', staffId: 5, staffName: 'Sara')],
      );

      await pumpBookingFlow(tester, stores: stores);

      await selectService(tester);
      await selectAnyStaff(tester);
      await systemBack(tester);
      await systemBack(tester);

      // Back at the service step, with the service still chosen — going back
      // must not wipe the flow.
      expect(find.text('Hair Cut'), findsOneWidget);
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      expect(find.text('أي موظف متاح'), findsOneWidget);
    });

    testWidgets('skips the standalone time index, like the AppBar arrow', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [slot('12:00', staffId: 5, staffName: 'Sara')],
      );

      await pumpBookingFlow(tester, stores: stores);

      await selectService(tester);
      await selectAnyStaff(tester);

      // Date + time are drawn as ONE screen, so picking a slot advances past
      // both steps at once.
      await tester.tap(find.text('12:00'));
      await tester.pumpAndSettle();

      await systemBack(tester);

      // Must return to the combined screen (day strip present), never to a
      // bare slot list at the `time` index the customer never saw.
      expect(find.text('اختر الموعد'), findsOneWidget);
      expect(find.text('اختر الوقت'), findsNothing);
    });

    testWidgets('leaves the flow only from the first step', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [slot('12:00', staffId: 5, staffName: 'Sara')],
      );

      final router = await pumpBookingFlow(tester, stores: stores);

      // First step is `service` — back here should exit to the storefront.
      await systemBack(tester);

      expect(currentLocation(router), '/storefront');
      expect(find.text('STOREFRONT_STUB'), findsOneWidget);
    });

    testWidgets('survives repeated back/forward cycles', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [slot('12:00', staffId: 5, staffName: 'Sara')],
      );

      final router = await pumpBookingFlow(tester, stores: stores);

      await selectService(tester);

      for (var cycle = 0; cycle < 3; cycle++) {
        await selectAnyStaff(tester);
        expect(find.text('اختر الموعد'), findsOneWidget);

        await systemBack(tester);
        expect(find.text('أي موظف متاح'), findsOneWidget);
      }

      expect(currentLocation(router), '/s/ABC12345/book');
      expect(tester.takeException(), isNull);
    });
  });
}
