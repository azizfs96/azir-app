import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/menu/menu_view.dart';
import 'package:wasla/features/stores/domain/menu.dart';

/// ============================================================================
/// THE MENU RENDERS LIKE JAHEZ (RestaurantEngine, R2)
///
///  · A top chip bar (best-sellers + each category) for navigation.
///  · Each section ALSO carries an inline header — the reference shows both.
///  · Best-sellers is a fixed 2-column grid; category items follow a
///    large(default) / compact-grid view toggle.
/// ============================================================================
void main() {
  Menu menu() => Menu.fromJson({
        'categories': [
          {
            'id': 1,
            'name': 'الحلويات',
            'items': [
              {'id': 1, 'name': 'بقلاوة', 'price': 99, 'is_featured': true, 'calories': 300,
                'description': 'حلوى شرقية'},
              {'id': 2, 'name': 'كنافة', 'price': 45},
            ],
          },
          {
            'id': 2,
            'name': 'المشروبات',
            'items': [
              {'id': 3, 'name': 'قهوة', 'price': 15},
            ],
          },
        ],
        'uncategorised': const [],
      });

  Future<void> pump(WidgetTester tester, {Menu? m}) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: Strings.supported,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          // MenuView is a sliver (its filter bar pins), so it lives in a
          // CustomScrollView rather than a box scroll view.
          body: CustomScrollView(
            slivers: [
              MenuView(
                storeToken: 'ABC',
                menu: m ?? menu(),
                brand: Colors.black,
                s: const Strings(Locale('ar')),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a chip AND an inline header exist for each section', (tester) async {
    await pump(tester);

    // Best-sellers: one chip + one section header = two occurrences.
    expect(find.text('الأكثر مبيعاً'), findsNWidgets(2));
    // Each category likewise appears as a chip and a header.
    expect(find.text('الحلويات'), findsNWidgets(2));
    expect(find.text('المشروبات'), findsNWidgets(2));
  });

  testWidgets('all sections are visible at once (chips navigate, not filter)',
      (tester) async {
    await pump(tester);

    // Dishes from every category are on screen together.
    expect(find.text('كنافة'), findsOneWidget); // الحلويات
    expect(find.text('قهوة'), findsOneWidget); // المشروبات
    // The featured dish shows in the best-sellers grid AND its own category.
    expect(find.text('بقلاوة'), findsNWidgets(2));
  });

  testWidgets('default is the compact grid; grid cards show calories', (tester) async {
    await pump(tester);

    // Default (Jahez-style): best-sellers AND every category are 2-column grids.
    expect(find.byType(GridView).evaluate().length, greaterThan(1));
    // A dish with calories shows them (flame + label) on its grid card.
    expect(find.text('300 سعرة'), findsWidgets);
  });

  testWidgets('the toggle switches categories to large cards', (tester) async {
    await pump(tester);

    // Default: multiple grids (best-sellers + categories).
    expect(find.byType(GridView).evaluate().length, greaterThan(1));

    await tester.ensureVisible(find.byIcon(Icons.crop_16_9_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.crop_16_9_rounded));
    await tester.pumpAndSettle();

    // Best-sellers stays a grid; categories become large single cards, so only
    // the best-sellers GridView remains. Calories are still shown.
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('300 سعرة'), findsWidgets);
  });

  testWidgets('shows the empty state when there is no menu', (tester) async {
    await pump(tester, m: const Menu(categories: [], uncategorised: []));
    expect(find.text('لا يوجد منيو بعد'), findsOneWidget);
  });
}
