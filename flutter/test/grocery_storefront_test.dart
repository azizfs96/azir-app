import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/grocery/grocery_product_card.dart';
import 'package:wasla/features/grocery/grocery_storefront.dart';
import 'package:wasla/features/menu/cart_controller.dart';
import 'package:wasla/features/stores/domain/storefront.dart';

/// The supermarket storefront: grocery fields parse, the discount badge and
/// unit show, "+" adds in ONE tap (no sheet), the stepper takes over, and a
/// product that is out of stock cannot be added.
void main() {
  Storefront market() => Storefront.fromJson({
        'store': {
          'token': 'MKT', 'name': 'سوق البركة', 'type': 'supermarket', 'brand_color': '#1F7A4D', 'is_open': true,
        },
        'configuration': {'order_delivery': true, 'order_pickup': false, 'order_dine_in': false},
        'flow': [
          {'step': 'menu', 'required': true},
          {'step': 'cart', 'required': true},
          {'step': 'payment', 'required': false, 'mode': 'cash_on_delivery'},
          {'step': 'confirm', 'required': true},
        ],
        'branches': const [],
        'menu': {
          'categories': [
            {
              'id': 1, 'name': 'ألبان', 'items': [
                {
                  'id': 10, 'name': 'حليب طازج', 'price': 6.25, 'compare_at_price': 7.5, 'discount_percent': 17,
                  'unit': '1 لتر', 'stock_quantity': 5, 'in_stock': true, 'is_featured': true, 'is_available': true,
                },
                {
                  'id': 11, 'name': 'بيض', 'price': 18, 'unit': '12 حبة', 'stock_quantity': 0, 'in_stock': false,
                  'is_available': true,
                },
              ],
            },
          ],
          'uncategorised': const [],
        },
      });

  Future<ProviderContainer> pump(WidgetTester tester, Storefront store) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    // The storefront pushes routes (categories, search, cart), so it needs a router.
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: GroceryStorefront(store: store, s: const Strings(Locale('ar')), token: 'MKT', onShare: () {}),
        ),
      ),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: Strings.supported,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  group('grocery model', () {
    test('a supermarket store parses its products and payment mode', () {
      final store = market();
      expect(store.isSupermarket, isTrue);
      expect(store.takesOrders, isTrue);
      expect(store.flow.firstWhere((f) => f.mode != null).mode, 'cash_on_delivery');

      final milk = store.menu!.categories.first.items.first;
      expect(milk.unit, '1 لتر');
      expect(milk.compareAtPrice, 7.5);
      expect(milk.discountPercent, 17);
      expect(milk.hasDiscount, isTrue);
      expect(milk.isOrderable, isTrue);

      final eggs = store.menu!.categories.first.items.last;
      expect(eggs.inStock, isFalse);
      expect(eggs.isOrderable, isFalse, reason: 'zero stock is sold out even if the merchant switch is on');
    });
  });

  group('grocery storefront', () {
    testWidgets('shows the discount badge, unit, and today\'s offers', (tester) async {
      await pump(tester, market());

      expect(find.text('-17%'), findsWidgets);
      expect(find.text('1 لتر'), findsWidgets);
      expect(find.text('عروض اليوم'), findsWidgets);
      expect(find.text('تسوق حسب القسم'), findsOneWidget);

      // The eggs sit in the category grid further down (slivers are lazy).
      await tester.scrollUntilVisible(find.text('بيض'), 300, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(find.text('نفد'), findsWidgets);
      // Let the SVG icon loaders finish before the tree is torn down.
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('"+" adds to the cart in one tap and becomes a stepper', (tester) async {
      final container = await pump(tester, market());

      // The first product card on screen is the milk (today's offers).
      final card = find.byType(GroceryProductCard).first;
      final plus = find.descendant(of: card, matching: find.byKey(const ValueKey('add'))).first;
      await tester.tap(plus);
      await tester.pump();

      final cart = container.read(cartProvider);
      expect(cart.storeToken, 'MKT');
      expect(cart.count, 1);
      expect(cart.lines.single.item.id, 10);
      expect(cart.lines.single.selectedOptionIds, isEmpty);

      // The stepper replaced the "+": tapping its plus increments.
      await tester.pumpAndSettle();
      final stepperPlus = find.descendant(of: card, matching: find.byIcon(Icons.add_rounded)).first;
      await tester.tap(stepperPlus);
      await tester.pump();
      expect(container.read(cartProvider).count, 2);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('a sold-out product cannot be added', (tester) async {
      final container = await pump(tester, market());

      // The eggs card (further down the page): its add button is disabled.
      await tester.scrollUntilVisible(find.text('بيض'), 300, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      final eggsCard = find.ancestor(of: find.text('بيض').first, matching: find.byType(GroceryProductCard));
      final plus = find.descendant(of: eggsCard, matching: find.byKey(const ValueKey('add'))).first;
      await tester.tap(plus);
      await tester.pump();

      expect(container.read(cartProvider).count, 0);
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
