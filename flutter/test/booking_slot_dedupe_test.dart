import 'package:flutter_test/flutter_test.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// BUG-8 — ONE TIME, ONE CHIP
///
/// With staff selection on and no stylist filter, the engine returns one slot
/// per (time, stylist) pair — correct data for someone choosing a person, but
/// the customer who tapped "any available" already said they do not care who.
/// They saw 12:00 twice, identical but for a small name underneath, and a
/// count inflated to match ("48 times available" for 24 distinct times).
///
/// The dedupe keeps the FIRST slot of each start time, so the staff the server
/// attached to it still flows into the booking payload as the assignment.
/// ============================================================================
void main() {
  Future<void> reachSlots(WidgetTester tester) async {
    await tester.tap(find.text('Hair Cut'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أي موظف متاح'));
    await tester.pumpAndSettle();
  }

  testWidgets('duplicate start times collapse into a single chip', (tester) async {
    final stores = FakeStoreRepository(
      storefront: storefrontFixture(),
      slotsFor: (_) => [
        slot('12:00', staffId: 5, staffName: 'Sara'),
        slot('12:00', staffId: 6, staffName: 'Reem'),
        slot('14:00', staffId: 6, staffName: 'Reem'),
      ],
    );

    await pumpBookingFlow(tester, stores: stores);
    await reachSlots(tester);

    expect(
      find.text('12:00'),
      findsOneWidget,
      reason: 'The same start time is rendered once per stylist.',
    );
    expect(find.text('14:00'), findsOneWidget);

    // The count reports distinct TIMES, not (time, stylist) pairs.
    expect(find.text('2 موعد متاح'), findsOneWidget);
    expect(find.text('3 موعد متاح'), findsNothing);
  });

  testWidgets('the deduped chip still carries a bookable assignment', (tester) async {
    final stores = FakeStoreRepository(
      storefront: storefrontFixture(),
      slotsFor: (_) => [
        slot('12:00', staffId: 5, staffName: 'Sara'),
        slot('12:00', staffId: 6, staffName: 'Reem'),
      ],
    );
    final bookings = FakeBookingRepository();

    await pumpBookingFlow(tester, stores: stores, bookings: bookings);
    await reachSlots(tester);

    await tester.tap(find.text('12:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأكيد الحجز').last);
    await tester.pumpAndSettle();

    // First-of-group wins: Sara's slot was kept, so her id is the assignment.
    expect(bookings.lastPayload?['staff_id'], 5);
    expect(bookings.lastPayload?['starts_at'], isNotEmpty);
  });

  testWidgets('slots at distinct times are never merged', (tester) async {
    final stores = FakeStoreRepository(
      storefront: storefrontFixture(),
      slotsFor: (_) => [
        slot('12:00', staffId: 5, staffName: 'Sara'),
        slot('12:30', staffId: 5, staffName: 'Sara'),
        slot('13:00', staffId: 5, staffName: 'Sara'),
      ],
    );

    await pumpBookingFlow(tester, stores: stores);
    await reachSlots(tester);

    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('12:30'), findsOneWidget);
    expect(find.text('13:00'), findsOneWidget);
    expect(find.text('3 موعد متاح'), findsOneWidget);
  });
}
