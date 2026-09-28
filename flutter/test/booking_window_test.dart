import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/features/booking/presentation/steps/date_step.dart';
import 'package:wasla/features/stores/domain/storefront.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// BUG-5 — THE MERCHANT DECIDES HOW FAR AHEAD CUSTOMERS CAN BOOK
///
/// The day strip was hard-coded to 30 days while the server's default is 60,
/// so a third of every merchant's bookable window was invisible in the app.
/// A merchant configured BELOW 30 had the opposite problem: the app offered
/// days the engine would never return slots for, which read as "fully booked"
/// rather than "outside the booking window".
///
/// The server has always published the real value at
/// policies.booking_window.max_advance_days — the client simply never read it.
/// ============================================================================
void main() {
  group('BUG-5 parsing the booking window', () {
    test('reads the merchant-configured window', () {
      expect(storefrontFixture(maxAdvanceDays: 60).maxAdvanceDays, 60);
      expect(storefrontFixture(maxAdvanceDays: 7).maxAdvanceDays, 7);
    });

    test('falls back when the server sends no booking window', () {
      // A store with no settings row still has to render something.
      expect(
        storefrontFixture().maxAdvanceDays,
        Storefront.defaultMaxAdvanceDays,
      );
    });

    test('clamps a nonsensical window rather than rendering an empty strip', () {
      // 0 days would generate a strip with no tiles at all — a screen the
      // customer cannot get past.
      expect(storefrontFixture(maxAdvanceDays: 0).maxAdvanceDays, 1);
      expect(storefrontFixture(maxAdvanceDays: 9999).maxAdvanceDays, 365);
    });
  });

  group('BUG-5 the strip honours the window', () {
    /// The number of day tiles the strip will generate.
    ///
    /// Asserting on rendered TEXT does not work here: the strip is a lazy
    /// ListView, so a day outside the viewport is never built and
    /// `findsNothing` passes whatever the window is. Day numbers also repeat
    /// across months, so "day 45" can match a tile inside a 30-day strip.
    /// Both made an earlier version of this test pass against the very bug it
    /// was meant to catch.
    int stripLength(WidgetTester tester) =>
        tester.widget<DateStrip>(find.byType(DateStrip)).maxAdvanceDays;

    Future<void> openDateStep(WidgetTester tester, int window) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(staffSelection: false, maxAdvanceDays: window),
        slotsFor: (_) => const [],
      );

      await pumpBookingFlow(tester, stores: stores);
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();
    }

    testWidgets('passes the merchant window down, not a hard-coded 30',
        (tester) async {
      await openDateStep(tester, 60);

      expect(
        stripLength(tester),
        60,
        reason: 'Days 31-60 are bookable for this merchant but unreachable in the app.',
      );
    });

    testWidgets('a short window offers only the days the merchant allows',
        (tester) async {
      await openDateStep(tester, 3);

      expect(
        stripLength(tester),
        3,
        reason: 'The app offers days the engine will never return slots for.',
      );
    });

    testWidgets('falls back to the default when the server omits the window',
        (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(staffSelection: false),
        slotsFor: (_) => const [],
      );

      await pumpBookingFlow(tester, stores: stores);
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      expect(stripLength(tester), Storefront.defaultMaxAdvanceDays);
    });
  });
}
