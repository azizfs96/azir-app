import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/features/booking/domain/booking_flow.dart';
import 'package:wasla/features/stores/domain/storefront.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// BUG-2 — "ANY AVAILABLE" MUST SURVIVE GOING BACK
///
/// The server names who will serve a slot. That name was written into the
/// answers map as if the customer had chosen it, so:
///
///   choose "any available" -> pick Sara's 12:00 -> back
///     => availability re-requested with staff_id=5
///     => every time only Reem could serve silently disappeared
///     => the staff step showed Sara selected, a choice never made
///
/// The selection and the assignment are two different facts. The CHOICE drives
/// what availability is requested; the ASSIGNMENT only reaches the payload.
/// ============================================================================
void main() {
  const sara = StoreStaff(id: 5, name: 'Sara');
  const service = StoreService(id: 1, name: 'Hair Cut', price: 100, durationMinutes: 60);

  List<FlowStep> merchantWithStaff() => [
        const FlowStep(type: FlowStepType.service, required: true),
        const FlowStep(type: FlowStepType.staff, required: true, allowAny: true),
        const FlowStep(type: FlowStepType.date, required: true),
        const FlowStep(type: FlowStepType.time, required: true),
        const FlowStep(type: FlowStepType.confirm, required: true),
      ];

  group('BUG-2 domain: assignment is not a selection', () {
    test('an assigned stylist never becomes the customer selection', () {
      final flow = BookingFlow(steps: merchantWithStaff())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.staff, null) // "any available"
        ..record(FlowStepType.date, DateTime(2026, 9, 15))
        ..assignStaff(sara)
        ..record(FlowStepType.time, '2026-09-15T12:00:00+03:00');

      expect(flow.staff, isNull, reason: 'The customer chose "any available".');
      expect(flow.assignedStaff, sara);

      // And the choice is still recorded as an explicit answer, so the step
      // does not start asking again.
      expect(flow.canAdvance, isTrue);
    });

    test('assigning a stylist does not clear the chosen time', () {
      final flow = BookingFlow(steps: merchantWithStaff())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.date, DateTime(2026, 9, 15))
        ..record(FlowStepType.time, '2026-09-15T12:00:00+03:00')
        ..assignStaff(sara);

      expect(flow.slotStartsAt, '2026-09-15T12:00:00+03:00');
    });

    test('the payload falls back to the assigned stylist', () {
      final flow = BookingFlow(steps: merchantWithStaff())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.staff, null)
        ..record(FlowStepType.date, DateTime(2026, 9, 15))
        ..assignStaff(sara)
        ..record(FlowStepType.time, '2026-09-15T12:00:00+03:00');

      expect(flow.toBookingPayload('8F72K')['staff_id'], 5);
    });

    test('an explicit choice outranks any assignment', () {
      const reem = StoreStaff(id: 6, name: 'Reem');

      final flow = BookingFlow(steps: merchantWithStaff())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.staff, reem)
        ..record(FlowStepType.date, DateTime(2026, 9, 15))
        ..assignStaff(sara)
        ..record(FlowStepType.time, '2026-09-15T12:00:00+03:00');

      expect(flow.toBookingPayload('8F72K')['staff_id'], 6);
    });

    test('changing the date drops a now-meaningless assignment', () {
      final flow = BookingFlow(steps: merchantWithStaff())
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.staff, null)
        ..record(FlowStepType.date, DateTime(2026, 9, 15))
        ..assignStaff(sara)
        ..record(FlowStepType.time, '2026-09-15T12:00:00+03:00')
        ..record(FlowStepType.date, DateTime(2026, 9, 16));

      expect(flow.assignedStaff, isNull);
      expect(flow.slotStartsAt, isNull);
      expect(flow.toBookingPayload('8F72K').containsKey('staff_id'), isFalse);
    });

    test('a merchant that hides staff still sends no staff_id', () {
      final flow = BookingFlow(steps: [
        const FlowStep(type: FlowStepType.service, required: true),
        const FlowStep(type: FlowStepType.date, required: true),
        const FlowStep(type: FlowStepType.time, required: true),
      ])
        ..record(FlowStepType.service, service)
        ..record(FlowStepType.date, DateTime(2026, 9, 15))
        // The server strips staff from slots for this merchant, so nothing is
        // ever assigned.
        ..record(FlowStepType.time, '2026-09-15T12:00:00+03:00');

      expect(flow.toBookingPayload('8F72K').containsKey('staff_id'), isFalse);
    });
  });

  group('BUG-2 screen: availability is requested for the CHOICE', () {
    testWidgets('going back after "any available" does not filter by stylist',
        (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [
          slot('12:00', staffId: 5, staffName: 'Sara'),
          slot('14:00', staffId: 6, staffName: 'Reem'),
        ],
      );

      await pumpBookingFlow(tester, stores: stores);

      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أي موظف متاح'));
      await tester.pumpAndSettle();

      expect(stores.lastQuery.staffId, isNull, reason: 'Fixture check.');

      // Pick a slot the server attributes to Sara, then go back.
      await tester.tap(find.text('12:00'));
      await tester.pumpAndSettle();
      await systemBack(tester);

      expect(
        stores.lastQuery.staffId,
        isNull,
        reason: 'Availability was narrowed to the assigned stylist after going back.',
      );
    });

    testWidgets('the staff step does not show a stylist the customer never chose',
        (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [slot('12:00', staffId: 5, staffName: 'Sara')],
      );

      await pumpBookingFlow(tester, stores: stores);

      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('أي موظف متاح'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('12:00'));
      await tester.pumpAndSettle();

      // Back to date+time, then back again to the staff step.
      await systemBack(tester);
      await systemBack(tester);

      // We are back on the staff step with "any available" still offered.
      expect(find.text('أي موظف متاح'), findsOneWidget);

      // Walk forward again without changing anything. If the assignment had
      // overwritten the choice, this would re-query filtered to Sara.
      await tester.tap(find.text('أي موظف متاح'));
      await tester.pumpAndSettle();

      expect(
        stores.lastQuery.staffId,
        isNull,
        reason: 'The customer\'s "any available" choice did not survive going back.',
      );
    });

    testWidgets('an explicit stylist choice still filters availability',
        (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [slot('12:00', staffId: 5, staffName: 'Sara')],
      );

      await pumpBookingFlow(tester, stores: stores);

      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sara'));
      await tester.pumpAndSettle();

      expect(stores.lastQuery.staffId, 5);

      await tester.tap(find.text('12:00'));
      await tester.pumpAndSettle();
      await systemBack(tester);

      // The customer DID choose Sara, so filtering is correct here.
      expect(stores.lastQuery.staffId, 5);
    });
  });
}
