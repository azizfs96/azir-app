import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../stores/domain/menu.dart';

/// ============================================================================
/// THE CART (RestaurantEngine, R2)
///
/// A per-store, in-memory cart. One line = a dish + the exact options chosen +
/// a quantity. The same dish with different options is two DISTINCT lines
/// (a plain burger and a cheese burger are not the same thing to add up), so a
/// signature over the selected option ids separates them.
///
/// Money here is for DISPLAY only. The server recomputes every total from the
/// item and option ids at order time (R3) — the client is never authoritative
/// about price.
/// ============================================================================

class CartLine {
  const CartLine({
    required this.item,
    required this.selectedOptionIds,
    required this.quantity,
  });

  final MenuItem item;

  /// Chosen option ids, flattened across all groups.
  final Set<int> selectedOptionIds;

  final int quantity;

  /// A stable key for "the same dish configured the same way".
  String get signature {
    final ids = selectedOptionIds.toList()..sort();
    return '${item.id}:${ids.join(",")}';
  }

  /// Unit price = base + every selected option's delta.
  double get unitPrice {
    var total = item.price;
    for (final group in item.optionGroups) {
      for (final option in group.options) {
        if (selectedOptionIds.contains(option.id)) total += option.priceDelta;
      }
    }
    return total;
  }

  double get lineTotal => unitPrice * quantity;

  /// The chosen options in menu order, for a readable line subtitle.
  List<MenuOption> get chosenOptions => [
        for (final group in item.optionGroups)
          for (final option in group.options)
            if (selectedOptionIds.contains(option.id)) option,
      ];

  CartLine copyWith({int? quantity}) => CartLine(
        item: item,
        selectedOptionIds: selectedOptionIds,
        quantity: quantity ?? this.quantity,
      );
}

class Cart {
  const Cart({this.storeToken, this.lines = const []});

  /// Which store this cart belongs to. Switching stores clears the cart —
  /// you cannot mix two restaurants' dishes in one order.
  final String? storeToken;
  final List<CartLine> lines;

  int get count => lines.fold(0, (sum, line) => sum + line.quantity);
  double get total => lines.fold(0, (sum, line) => sum + line.lineTotal);
  bool get isEmpty => lines.isEmpty;
}

class CartController extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

  /// Add a configured dish. Adding the same signature bumps quantity instead
  /// of creating a duplicate line.
  void add(String storeToken, CartLine line) {
    // A cart belongs to one store; arriving at a different one resets it.
    final base = state.storeToken == storeToken
        ? state
        : Cart(storeToken: storeToken);

    final existing = base.lines.indexWhere((l) => l.signature == line.signature);

    final lines = [...base.lines];
    if (existing >= 0) {
      lines[existing] = lines[existing].copyWith(
        quantity: lines[existing].quantity + line.quantity,
      );
    } else {
      lines.add(line);
    }

    state = Cart(storeToken: storeToken, lines: lines);
  }

  void setQuantity(String signature, int quantity) {
    if (quantity <= 0) {
      remove(signature);
      return;
    }
    state = Cart(
      storeToken: state.storeToken,
      lines: [
        for (final line in state.lines)
          line.signature == signature ? line.copyWith(quantity: quantity) : line,
      ],
    );
  }

  void remove(String signature) {
    state = Cart(
      storeToken: state.storeToken,
      lines: state.lines.where((l) => l.signature != signature).toList(),
    );
  }

  void clear() => state = Cart(storeToken: state.storeToken);

  /// Replace the whole cart in one shot — used by reorder, which rebuilds a
  /// past order's lines and drops whatever was there before.
  void replaceAll(String storeToken, List<CartLine> lines) {
    state = Cart(storeToken: storeToken, lines: lines);
  }
}

/// One cart at a time — the customer is in one restaurant.
final cartProvider = NotifierProvider<CartController, Cart>(CartController.new);

/// The cart's contents for THIS store only (empty once they switch stores).
final cartForStoreProvider = Provider.family<Cart, String>((ref, token) {
  final cart = ref.watch(cartProvider);
  return cart.storeToken == token ? cart : const Cart();
});
