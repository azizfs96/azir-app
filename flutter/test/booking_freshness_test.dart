import 'package:flutter_test/flutter_test.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// BUG-9 — MERCHANT DATA MUST BE FRESH WHEN A BOOKING STARTS
/// BUG-10 — A FAILED STOREFRONT LOAD MUST BE RECOVERABLE
///
/// The storefront provider cached per token for the whole session. A customer
/// who kept the app open saw launch-day prices, could book a service the
/// merchant had since deactivated, and walked a step list the merchant had
/// since reconfigured. And if the one storefront request failed on entry, the
/// flow showed "حدث خطأ" with no way forward — backing out and re-entering was
/// the only recovery.
/// ============================================================================
void main() {
  group('BUG-9 storefront refresh', () {
    testWidgets('re-entering the flow refetches the storefront', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(staffSelection: false),
        slotsFor: (_) => [slot('12:00')],
      );

      final router = await pumpBookingFlow(tester, stores: stores);

      // First entry: the resolve that populated the provider, plus the
      // entry refresh.
      final afterFirstEntry = stores.resolveCalls;
      expect(afterFirstEntry, greaterThanOrEqualTo(1));

      // Leave from step 1, then come back — a new visit, possibly hours later.
      await systemBack(tester);
      expect(find.text('STOREFRONT_STUB'), findsOneWidget);

      router.push('/s/ABC12345/book');
      await tester.pumpAndSettle();

      expect(
        stores.resolveCalls,
        greaterThan(afterFirstEntry),
        reason: 'The booking flow served the session-cached storefront '
            'without ever asking the server again.',
      );
    });

    testWidgets('an unchanged step list keeps the in-progress flow', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(staffSelection: false),
        slotsFor: (_) => [slot('12:00')],
      );

      await pumpBookingFlow(tester, stores: stores);

      // Answer the first step, then let the entry refresh land (it resolves
      // the same configuration). The flow must still be on step 2 with the
      // service kept — a refresh is not a reset.
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      expect(find.text('اختر الموعد'), findsOneWidget);
    });
  });

  group('BUG-10 load failure', () {
    testWidgets('shows retry, and retry recovers', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(staffSelection: false),
        slotsFor: (_) => [slot('12:00')],
      )..resolveError = Exception('network down');

      await pumpBookingFlow(tester, stores: stores);

      // The dead end, now with a way out.
      expect(find.text('حدث خطأ'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);

      // Network comes back; the customer taps retry.
      stores.resolveError = null;
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();

      expect(
        find.text('Hair Cut'),
        findsOneWidget,
        reason: 'Retry did not reload the storefront into the flow.',
      );
    });
  });
}
