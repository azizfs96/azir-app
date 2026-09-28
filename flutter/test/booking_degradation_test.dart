import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/core/router/app_router.dart';
import 'package:wasla/features/booking/data/booking_repository.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// BUG-11 — DEGRADE ON A MALFORMED SERVER FLOW, NEVER CRASH
/// BUG-12 — SAY WHAT FAILED, NOT "SOMETHING WENT WRONG"
/// BUG-13 — EVERY EMPTY STATE EXPLAINS WHAT TO DO NEXT
///
/// The app's own contract is that the flow is server data and unknown shapes
/// are skipped, not fatal. Two places broke that promise with a `!`:
/// `flow.serviceId!` (a step list ordering `date` before `service`) and the
/// confirmation route's `state.extra!` (a process restart or hand-typed link).
/// Both were red-screen crashes on payloads the contract allows.
/// ============================================================================
void main() {
  group('BUG-11 malformed flow', () {
    testWidgets('date before service renders an error, not a crash', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(flowOverride: [
          {'step': 'date', 'required': true},
          {'step': 'time', 'required': true},
          {'step': 'service', 'required': true},
          {'step': 'confirm', 'required': true},
        ]),
        slotsFor: (_) => [slot('12:00')],
      );

      await pumpBookingFlow(tester, stores: stores);

      expect(tester.takeException(), isNull,
          reason: 'A malformed step list crashed the flow.');
      expect(find.text('حدث خطأ'), findsOneWidget);
    });

    test('the confirmed route redirects home when the booking is missing', () {
      // A restart or a hand-typed deep link arrives with no extra.
      expect(confirmedRouteGuard(null), '/');
      expect(confirmedRouteGuard('not a booking'), '/');

      // The normal pushReplacement carries the booking and passes through.
      const booking = BookingResult(
        id: 1,
        reference: 'WSL-1',
        status: 'confirmed',
        startsAt: '2026-09-01T12:00:00+03:00',
        price: 100,
        currency: 'SAR',
      );
      expect(confirmedRouteGuard(booking), isNull);
    });
  });

  group('BUG-12 availability failure names itself', () {
    testWidgets('the combined screen says the TIMES failed, and retry reloads',
        (tester) async {
      var fail = true;

      final stores = FakeStoreRepository(
        storefront: storefrontFixture(staffSelection: false),
        slotsFor: (_) {
          if (fail) throw Exception('boom');
          return [slot('12:00')];
        },
      );

      await pumpBookingFlow(tester, stores: stores);
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      expect(find.text('تعذّر تحميل الأوقات المتاحة. حاول مرة أخرى.'),
          findsOneWidget);
      expect(find.text('حدث خطأ'), findsNothing);

      fail = false;
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();

      expect(find.text('12:00'), findsOneWidget,
          reason: 'Retry did not reload availability.');
    });
  });

  group('BUG-13 empty state guidance', () {
    testWidgets('the STANDALONE time step explains what to do next', (tester) async {
      // `payment` between `date` and `time` makes them non-adjacent, so the
      // customer walks the plain DateStep and then the standalone TimeStep —
      // the screen whose empty state used to be a bare sentence.
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(flowOverride: [
          {'step': 'service', 'required': true},
          {'step': 'date', 'required': true},
          {'step': 'payment', 'required': false, 'mode': 'pay_at_store'},
          {'step': 'time', 'required': true},
          {'step': 'confirm', 'required': true},
        ]),
        slotsFor: (_) => const [], // fully booked
      );

      await pumpBookingFlow(tester, stores: stores);

      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.tap(find.text('${tomorrow.day}').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();

      // What happened AND what to do about it — same as the combined screen.
      expect(find.text('لا توجد أوقات متاحة في هذا اليوم'), findsOneWidget);
      expect(
        find.text('جرّب يوماً آخر'),
        findsOneWidget,
        reason: 'The empty state explains nothing about what to do next.',
      );
    });
  });
}
