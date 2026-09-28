import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/core/theme/app_theme.dart';
import 'package:wasla/features/booking/presentation/steps/date_step.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// BUG-6 — THE CHOSEN TIME MUST STILL LOOK CHOSEN
/// BUG-7 — THE DAY STRIP MUST SHOW THE CHOSEN DAY
///
/// Returning to the date+time screen restored the DATE but nothing else: the
/// slot list came back with no chip marked, and the strip rendered from today
/// so a selection three weeks out sat off-screen. The customer had to remember
/// what they picked and hunt for it again.
/// ============================================================================
void main() {
  /// The chip's own Material carries the selected fill, so this reads the
  /// rendered result rather than a private widget type.
  Material chipMaterial(WidgetTester tester, String time) {
    return tester.widget<Material>(
      find
          .ancestor(of: find.text(time), matching: find.byType(Material))
          .first,
    );
  }

  group('BUG-6 chosen time is restored', () {
    testWidgets('the picked slot renders as selected on return', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(staffSelection: false),
        slotsFor: (_) => [slot('12:00'), slot('14:00')],
      );

      await pumpBookingFlow(tester, stores: stores);
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      // Nothing is selected on first arrival.
      expect(chipMaterial(tester, '12:00').color, Colors.white);

      await tester.tap(find.text('12:00'));
      await tester.pumpAndSettle();
      await systemBack(tester);

      expect(
        chipMaterial(tester, '12:00').color,
        AppColors.ink900,
        reason: 'The previously chosen time is not marked as selected.',
      );

      // ...and only that one.
      expect(chipMaterial(tester, '14:00').color, Colors.white);
    });

    testWidgets('switching day clears the highlight', (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(staffSelection: false),
        slotsFor: (query) => [
          slot('12:00', day: query.date),
          slot('14:00', day: query.date),
        ],
      );

      await pumpBookingFlow(tester, stores: stores);
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('12:00'));
      await tester.pumpAndSettle();
      await systemBack(tester);

      expect(chipMaterial(tester, '12:00').color, AppColors.ink900);

      // Pick a different day: the old slot belongs to another date, so nothing
      // should stay highlighted.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await tester.tap(find.text('${tomorrow.day}').first);
      await tester.pumpAndSettle();

      expect(chipMaterial(tester, '12:00').color, Colors.white);
    });
  });

  group('BUG-7 day strip scrolls to the chosen day', () {
    /// Mount a DateStrip on its own. The full-flow version of this test had to
    /// scroll a nested RTL list to reach a far date before it could even make
    /// the assertion, which tested the driver more than the app.
    Future<ScrollController> pumpStrip(WidgetTester tester, DateTime? selected) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: Strings.supported,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: DateStrip(selected: selected, onSelected: (_) {}, maxAdvanceDays: 30),
          ),
        ),
      );

      await tester.pumpAndSettle();

      return tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
    }

    testWidgets('scrolls a far-out selection into view', (tester) async {
      final target = DateTime.now().add(const Duration(days: 20));
      final controller = await pumpStrip(tester, target);

      expect(
        controller.offset,
        greaterThan(0),
        reason: 'The strip stayed at today, leaving the chosen day off-screen.',
      );

      // And the chosen tile is genuinely rendered now.
      expect(find.text('${target.day}'), findsOneWidget);
    });

    testWidgets('stays at today when the selection is today', (tester) async {
      final controller = await pumpStrip(tester, DateTime.now());

      expect(controller.offset, 0);
    });

    testWidgets('stays at today when nothing is selected', (tester) async {
      final controller = await pumpStrip(tester, null);

      expect(controller.offset, 0);
    });

    testWidgets('never scrolls past the end of the strip', (tester) async {
      final last = DateTime.now().add(const Duration(days: 29));
      final controller = await pumpStrip(tester, last);

      expect(controller.offset, lessThanOrEqualTo(controller.position.maxScrollExtent));
    });
  });
}
