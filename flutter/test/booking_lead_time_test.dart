import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/booking/presentation/steps/date_step.dart';

import 'support/booking_harness.dart';

/// ============================================================================
/// MIN LEAD TIME — DO NOT OFFER DAYS THE MERCHANT'S NOTICE HAS CLOSED
///
/// The engine refuses any slot before now + min_lead_time_minutes; the app
/// never read the value. A customer opening the flow at 23:30 with the default
/// 60-minute lead landed on a "today" tile the engine always answers with an
/// empty list — rendered as "لا توجد أوقات متاحة", which reads as fully booked
/// when the truth is "this merchant needs more notice".
/// ============================================================================
void main() {
  /// A lead that is GUARANTEED to close out today and nothing more, whatever
  /// the wall clock says while the test runs.
  int leadClosingToday() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);

    return midnight.difference(now).inMinutes + 120;
  }

  group('parsing', () {
    test('reads the merchant lead time', () {
      expect(storefrontFixture(minLeadMinutes: 1440).minLeadTimeMinutes, 1440);
    });

    test('defaults to zero when the server sends none', () {
      expect(storefrontFixture().minLeadTimeMinutes, 0);
    });

    test('clamps a negative value to zero', () {
      expect(storefrontFixture(minLeadMinutes: -5).minLeadTimeMinutes, 0);
    });
  });

  group('firstBookableDay', () {
    test('a lead inside today keeps today', () {
      expect(
        firstBookableDay(DateTime(2026, 8, 17, 10, 0), 60),
        DateTime(2026, 8, 17),
      );
    });

    test('a lead crossing midnight moves to tomorrow', () {
      expect(
        firstBookableDay(DateTime(2026, 8, 17, 23, 0), 120),
        DateTime(2026, 8, 18),
      );
    });

    test('a 48-hour lead skips two days', () {
      expect(
        firstBookableDay(DateTime(2026, 8, 17, 10, 0), 2880),
        DateTime(2026, 8, 19),
      );
    });

    test('zero lead is today', () {
      expect(
        firstBookableDay(DateTime(2026, 8, 17, 23, 59), 0),
        DateTime(2026, 8, 17),
      );
    });
  });

  group('the strip', () {
    Future<void> pumpStrip(WidgetTester tester, int lead) async {
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
            body: DateStrip(
              onSelected: (_) {},
              maxAdvanceDays: 30,
              leadTimeMinutes: lead,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
    }

    testWidgets('a closed today is not offered at all', (tester) async {
      await pumpStrip(tester, leadClosingToday());

      expect(
        find.text('اليوم'),
        findsNothing,
        reason: 'The strip still offers a day the engine will always answer empty.',
      );
      expect(find.text('غداً'), findsOneWidget);
    });

    testWidgets('zero lead still starts at today', (tester) async {
      await pumpStrip(tester, 0);

      expect(find.text('اليوم'), findsOneWidget);
    });
  });

  group('the flow', () {
    testWidgets('the default availability request skips the closed day',
        (tester) async {
      final stores = FakeStoreRepository(
        storefront: storefrontFixture(
          staffSelection: false,
          minLeadMinutes: leadClosingToday(),
        ),
        slotsFor: (_) => [slot('12:00')],
      );

      await pumpBookingFlow(tester, stores: stores);
      await tester.tap(find.text('Hair Cut'));
      await tester.pumpAndSettle();

      final tomorrow = DateTime.now().add(const Duration(days: 1));

      expect(
        stores.lastQuery.date.day,
        tomorrow.day,
        reason: 'The flow still queries a day the merchant\'s notice has closed.',
      );
    });
  });
}
