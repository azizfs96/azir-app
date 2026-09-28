import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/menu/cart_controller.dart';
import 'package:wasla/features/menu/item_sheet.dart';
import 'package:wasla/features/stores/domain/menu.dart';

/// ============================================================================
/// THE ITEM SHEET GATES ON THE OPTION RULES (RestaurantEngine, R2)
///
/// The add button must obey the same selection rules the backend enforces: a
/// required single-choice group blocks until it has a pick (though it defaults
/// to the first option so the customer is rarely stuck), and a multi group is
/// capped at maxSelect. Adding produces a correctly-priced cart line.
/// ============================================================================
void main() {
  MenuItem burger({bool sizeRequired = true}) => MenuItem.fromJson({
        'id': 1,
        'name': 'برجر',
        'price': 30,
        'option_groups': [
          {
            'id': 10,
            'name': 'الحجم',
            'min_select': sizeRequired ? 1 : 0,
            'max_select': 1,
            'options': [
              {'id': 100, 'name': 'وسط', 'price_delta': 0},
              {'id': 101, 'name': 'كبير', 'price_delta': 5},
            ],
          },
          {
            'id': 11,
            'name': 'الإضافات',
            'min_select': 0,
            'max_select': 1, // at most one extra
            'options': [
              {'id': 110, 'name': 'جبن', 'price_delta': 3},
              {'id': 111, 'name': 'بيكون', 'price_delta': 6},
            ],
          },
        ],
      });

  Future<ProviderContainer> pump(WidgetTester tester, MenuItem item) async {
    // A phone-sized surface so the near-full-height sheet has room for its image
    // header and every option (the default 800×600 is too short).
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: Strings.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showItemSheet(
                  context,
                  storeToken: 'ABC',
                  item: item,
                  brand: Colors.black,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a required single group defaults to its first option and can add',
      (tester) async {
    final container = await pump(tester, burger());

    // "وسط" (first option) is pre-selected, so add is enabled immediately.
    await tester.tap(find.textContaining('أضف'));
    await tester.pumpAndSettle();

    final cart = container.read(cartProvider);
    expect(cart.lines.length, 1);
    expect(cart.lines.single.unitPrice, 30); // base + وسط(0)
  });

  testWidgets('choosing a larger size updates the add price live', (tester) async {
    await pump(tester, burger());

    await tester.tap(find.text('كبير'));
    await tester.pumpAndSettle();

    // 30 + 5 = 35 shown on the button.
    expect(find.textContaining('35'), findsOneWidget);
  });

  testWidgets('a single-choice extras group swaps rather than stacks', (tester) async {
    final container = await pump(tester, burger());

    // The taller image header can push the extras below the fold — bring each
    // option into view before tapping it.
    await tester.ensureVisible(find.text('جبن'));
    await tester.tap(find.text('جبن')); // +3
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('بيكون'));
    await tester.tap(find.text('بيكون')); // +6, replaces جبن (max 1)
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('أضف'));
    await tester.pumpAndSettle();

    // base 30 + وسط 0 + بيكون 6 = 36 (NOT 39 — cheese was swapped out).
    expect(container.read(cartProvider).lines.single.unitPrice, 36);
  });
}
