import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wasla/features/menu/cart_controller.dart';
import 'package:wasla/features/stores/domain/menu.dart';
import 'package:wasla/features/stores/domain/storefront.dart';

/// ============================================================================
/// RESTAURANT MENU + CART (RestaurantEngine, R2)
///
/// The money maths lives in CartLine/Cart and must be exactly right — even
/// though the server re-computes it authoritatively at order time, a wrong
/// figure here is a wrong figure in the customer's face. And the cart's
/// identity rules (same dish + same options = one line; a different store
/// resets everything) are the difference between a coherent order and a
/// jumbled one.
/// ============================================================================
void main() {
  // A burger: base 30, a required size (وسط +0 / كبير +5) and optional extras
  // (جبن +3 / بيكون +6).
  MenuItem burger() => MenuItem.fromJson({
        'id': 1,
        'name': 'برجر',
        'price': 30,
        'is_featured': true,
        'option_groups': [
          {
            'id': 10,
            'name': 'الحجم',
            'min_select': 1,
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
            'max_select': 2,
            'options': [
              {'id': 110, 'name': 'جبن', 'price_delta': 3},
              {'id': 111, 'name': 'بيكون', 'price_delta': 6},
            ],
          },
        ],
      });

  group('menu parsing', () {
    test('the storefront payload yields a menu with featured items', () {
      final store = Storefront.fromJson({
        'store': {'token': 'ABC', 'name': 'Balad', 'type': 'restaurant'},
        'configuration': const <String, dynamic>{},
        'flow': const <dynamic>[],
        'services': const <dynamic>[],
        'staff': const <dynamic>[],
        'branches': const <dynamic>[],
        'menu': {
          'categories': [
            {
              'id': 1,
              'name': 'البرجر',
              'items': [burger().let()],
            },
          ],
          'uncategorised': const [],
        },
      });

      expect(store.isRestaurant, isTrue);
      expect(store.menu, isNotNull);
      expect(store.menu!.categories.single.name, 'البرجر');
      expect(store.menu!.featured.single.name, 'برجر');
    });

    test('a beauty storefront has no menu', () {
      final store = Storefront.fromJson({
        'store': {'token': 'XYZ', 'name': 'Glow', 'type': 'beauty_wellness'},
        'configuration': const <String, dynamic>{},
        'flow': const <dynamic>[],
        'services': const <dynamic>[],
        'staff': const <dynamic>[],
        'branches': const <dynamic>[],
      });

      expect(store.isRestaurant, isFalse);
      expect(store.menu, isNull);
    });

    test('single vs multi choice is read from max_select', () {
      final groups = burger().optionGroups;
      expect(groups[0].isSingleChoice, isTrue);
      expect(groups[0].isRequired, isTrue);
      expect(groups[1].isSingleChoice, isFalse);
      expect(groups[1].isRequired, isFalse);
    });
  });

  group('cart line pricing', () {
    test('unit price is base plus every selected delta', () {
      final line = CartLine(
        item: burger(),
        selectedOptionIds: {101, 110}, // كبير +5, جبن +3
        quantity: 2,
      );

      expect(line.unitPrice, 38); // 30 + 5 + 3
      expect(line.lineTotal, 76); // ×2
    });

    test('the cheapest configuration is just the base', () {
      final line = CartLine(item: burger(), selectedOptionIds: {100}, quantity: 1);
      expect(line.unitPrice, 30);
    });
  });

  group('cart controller', () {
    late ProviderContainer container;
    CartController cart() => container.read(cartProvider.notifier);

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('adding the same dish+options merges into one line', () {
      final line = CartLine(item: burger(), selectedOptionIds: {101}, quantity: 1);

      cart().add('ABC', line);
      cart().add('ABC', CartLine(item: burger(), selectedOptionIds: {101}, quantity: 2));

      final state = container.read(cartProvider);
      expect(state.lines.length, 1, reason: 'Identical configurations must not split.');
      expect(state.lines.single.quantity, 3);
      expect(state.count, 3);
    });

    test('the same dish with DIFFERENT options is a separate line', () {
      cart().add('ABC', CartLine(item: burger(), selectedOptionIds: {100}, quantity: 1));
      cart().add('ABC', CartLine(item: burger(), selectedOptionIds: {101}, quantity: 1));

      expect(container.read(cartProvider).lines.length, 2);
    });

    test('the running total sums every line', () {
      cart().add('ABC', CartLine(item: burger(), selectedOptionIds: {101, 111}, quantity: 1)); // 41
      cart().add('ABC', CartLine(item: burger(), selectedOptionIds: {100}, quantity: 2)); // 60

      expect(container.read(cartProvider).total, 101);
    });

    test('arriving at a different store clears the cart', () {
      cart().add('ABC', CartLine(item: burger(), selectedOptionIds: {100}, quantity: 1));
      cart().add('XYZ', CartLine(item: burger(), selectedOptionIds: {100}, quantity: 1));

      final state = container.read(cartProvider);
      expect(state.storeToken, 'XYZ');
      expect(state.lines.length, 1, reason: "Two restaurants' dishes must not mix.");
    });

    test('cartForStore hides another store\'s cart', () {
      cart().add('ABC', CartLine(item: burger(), selectedOptionIds: {100}, quantity: 1));

      expect(container.read(cartForStoreProvider('ABC')).count, 1);
      expect(container.read(cartForStoreProvider('XYZ')).count, 0);
    });

    test('setting quantity to zero removes the line', () {
      final line = CartLine(item: burger(), selectedOptionIds: {100}, quantity: 1);
      cart().add('ABC', line);
      cart().setQuantity(line.signature, 0);

      expect(container.read(cartProvider).isEmpty, isTrue);
    });
  });
}

extension on MenuItem {
  /// The parsing tests build a burger via fromJson, then need it back as the
  /// same JSON shape for the nested category. Round-tripping the fields keeps
  /// the fixture in one place.
  Map<String, dynamic> let() => {
        'id': id,
        'name': name,
        'price': price,
        'is_featured': isFeatured,
        'option_groups': [
          for (final g in optionGroups)
            {
              'id': g.id,
              'name': g.name,
              'min_select': g.minSelect,
              'max_select': g.maxSelect,
              'options': [
                for (final o in g.options)
                  {'id': o.id, 'name': o.name, 'price_delta': o.priceDelta},
              ],
            },
        ],
      };
}
