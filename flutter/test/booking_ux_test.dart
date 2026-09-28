import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// UX DEFECTS FROM THE AUDIT
///
/// - The progress bar counted STEPS while the customer sees SCREENS: adjacent
///   date+time render as one screen, so the bar jumped by two there and its
///   value never corresponded to anything visible.
/// - "Any available" could never look chosen on the way back — the card had no
///   selected treatment at all, unlike every named stylist's card.
/// ============================================================================
void main() {
  double barValue(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
      .value!;

  group('progress bar tracks screens', () {
    testWidgets('advances by ONE visible screen at a time', (tester) async {
      // Steps: service, date, time, payment, confirm (5)
      // Screens: service, date+time, payment, confirm (4)
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(staffSelection: false),
        slotsFor: (_) => [slot('12:00')],
      );

      await pumpBookingFlow(tester, stores: stores);

      expect(barValue(tester), closeTo(1 / 4, 0.001),
          reason: 'Screen 1 of 4 must read 25%.');

      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      expect(barValue(tester), closeTo(2 / 4, 0.001),
          reason: 'The combined date+time screen is ONE screen, not two.');

      await tester.tap(find.text('12:00'));
      await tester.pumpAndSettle();

      // Picking a slot answers both date and time — next screen is payment.
      expect(barValue(tester), closeTo(3 / 4, 0.001));

      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();

      expect(barValue(tester), closeTo(4 / 4, 0.001));
    });
  });

  group('"any available" looks chosen', () {
    Finder anyCardBorder() => find.ancestor(
          of: find.text('أي موظف متاح'),
          matching: find.byWidgetPredicate(
            (widget) => widget is Container && widget.decoration is BoxDecoration,
          ),
        );

    double anyCardBorderWidth(WidgetTester tester) {
      final container = tester.widget<Container>(anyCardBorder().first);
      final decoration = container.decoration! as BoxDecoration;

      return (decoration.border! as Border).top.width;
    }

    testWidgets('the card shows selection after a round trip', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [slot('12:00', staffId: 5, staffName: 'Sara')],
      );

      await pumpBookingFlow(tester, stores: stores);
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      // Not chosen yet: hairline border, no check.
      expect(anyCardBorderWidth(tester), 1.0);
      expect(
        find.descendant(of: anyCardBorder().first, matching: find.byIcon(Icons.check_rounded)),
        findsNothing,
      );

      await tester.tap(find.text('أي موظف متاح'));
      await tester.pumpAndSettle();
      await systemBack(tester);

      // Back on the staff step: the answer the customer gave is visible.
      expect(
        anyCardBorderWidth(tester),
        1.6,
        reason: 'The chosen "any available" card is indistinguishable from unchosen.',
      );
      expect(
        find.descendant(of: anyCardBorder().first, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget,
      );
    });

    testWidgets('choosing a named stylist leaves the any-card unselected',
        (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(),
        slotsFor: (_) => [slot('12:00')],
      );

      await pumpBookingFlow(tester, stores: stores);
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sara'));
      await tester.pumpAndSettle();
      await systemBack(tester);

      expect(anyCardBorderWidth(tester), 1.0);
    });
  });
}
