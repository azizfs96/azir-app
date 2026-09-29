import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wasla/core/localization/strings.dart';
import 'package:wasla/features/menu/cart_controller.dart';
import 'package:wasla/features/menu/cart_screen.dart';
import 'package:wasla/features/menu/order_repository.dart';
import 'package:wasla/features/stores/data/store_repository.dart';
import 'package:wasla/features/stores/domain/menu.dart';
import 'package:wasla/features/stores/domain/storefront.dart';

/// ============================================================================
/// CHECKOUT (RestaurantEngine, R3) — placing an order from the cart.
///
/// The cart footer must submit only INTENTS (item id, option ids, quantity),
/// clear the cart on success, and route to tracking. It must never trust its
/// own total — the placed order's total comes back from the server.
/// ============================================================================
class _FakeOrderRepository implements OrderRepository {
  _FakeOrderRepository({this.fail = false});

  bool fail;
  Map<String, dynamic>? lastBody;

  @override
  Future<OrderResult> place({
    required String storeToken,
    required String fulfillmentType,
    required List<CartLine> lines,
    String? notes,
    String? tableNumber,
    int? addressId,
    int? carId,
    int? branchId,
  }) async {
    lastBody = {
      'store_token': storeToken,
      'fulfillment_type': fulfillmentType,
      'table_number': tableNumber,
      'address_id': addressId,
      'branch_id': branchId,
      'notes': notes,
      'items': [
        for (final l in lines)
          {'item_id': l.item.id, 'quantity': l.quantity, 'option_ids': l.selectedOptionIds.toList()},
      ],
    };
    if (fail) throw Exception('boom');
    return const OrderResult(
      id: 7, reference: 'WSL-7', status: 'placed', total: 41, storeToken: 'ABC');
  }

  @override
  Future<OrderResult> get(int id) async =>
      const OrderResult(id: 7, reference: 'WSL-7', status: 'placed', total: 41);

  @override
  Future<List<OrderResult>> myOrders(String filter) async => const [];

  @override
  Future<OrderResult> cancel(int id) async =>
      const OrderResult(id: 7, reference: 'WSL-7', status: 'cancelled', total: 41);
}

void main() {
  MenuItem burger() => MenuItem.fromJson({
        'id': 1, 'name': 'برجر', 'price': 30,
        'option_groups': [
          {'id': 10, 'name': 'الحجم', 'min_select': 1, 'max_select': 1,
            'options': [{'id': 100, 'name': 'وسط', 'price_delta': 0}]},
        ],
      });

  Future<(ProviderContainer, _FakeOrderRepository, GoRouter)> pumpCart(
    WidgetTester tester, {
    bool fail = false,
  }) async {
    final repo = _FakeOrderRepository(fail: fail);
    // A restaurant storefront whose fulfilment pills the cart renders from.
    final store = Storefront.fromJson({
      'store': {'token': 'ABC', 'name': 'برجر', 'type': 'restaurant', 'currency': 'SAR'},
      'configuration': {'order_pickup': true, 'order_dine_in': true},
      'flow': [
        {'step': 'menu', 'required': true},
        {'step': 'cart', 'required': true},
      ],
      'branches': const [],
    });
    final container = ProviderContainer(overrides: [
      orderRepositoryProvider.overrideWithValue(repo),
      storefrontProvider('ABC').overrideWith((ref) async => store),
    ]);
    addTearDown(container.dispose);

    // Pre-fill the cart for store ABC.
    container.read(cartProvider.notifier).add(
          'ABC',
          CartLine(item: burger(), selectedOptionIds: {100}, quantity: 1),
        );

    final router = GoRouter(
      initialLocation: '/s/ABC/cart',
      routes: [
        GoRoute(path: '/s/:token/cart', builder: (_, _) => const CartScreen(token: 'ABC')),
        GoRoute(path: '/orders/:id', builder: (_, state) =>
            Scaffold(body: Text('TRACK_${state.pathParameters['id']}'))),
      ],
    );

    await tester.pumpWidget(UncontrolledProviderScope(
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
    ));
    await tester.pumpAndSettle();
    return (container, repo, router);
  }

  testWidgets('placing an order submits intents, clears the cart, tracks it',
      (tester) async {
    final (container, repo, _) = await pumpCart(tester);

    await tester.tap(find.text('إتمام الطلب'));
    await tester.pumpAndSettle();

    // Submitted the right intent — item id + option ids + quantity, pickup.
    expect(repo.lastBody!['fulfillment_type'], 'pickup');
    expect((repo.lastBody!['items'] as List).single, {
      'item_id': 1, 'quantity': 1, 'option_ids': [100],
    });

    // Cart cleared and routed to tracking.
    expect(container.read(cartProvider).isEmpty, isTrue);
    expect(find.text('TRACK_7'), findsOneWidget);
  });

  testWidgets('choosing dine-in sends the fulfillment type', (tester) async {
    final (_, repo, _) = await pumpCart(tester);

    await tester.tap(find.text('داخل المطعم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إتمام الطلب'));
    await tester.pumpAndSettle();

    expect(repo.lastBody!['fulfillment_type'], 'dine_in');
  });

  testWidgets('a failed placement keeps the cart and shows an error', (tester) async {
    final (container, _, _) = await pumpCart(tester, fail: true);

    await tester.tap(find.text('إتمام الطلب'));
    await tester.pumpAndSettle();

    expect(find.text('تعذّر إتمام الطلب. حاول مرة أخرى.'), findsOneWidget);
    expect(container.read(cartProvider).isEmpty, isFalse, reason: 'A failed order must not lose the cart.');
    expect(find.text('TRACK_7'), findsNothing);
  });
}
