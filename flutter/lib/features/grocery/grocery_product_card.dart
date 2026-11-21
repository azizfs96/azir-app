import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../menu/cart_controller.dart';
import '../menu/item_sheet.dart';
import '../stores/domain/menu.dart';
import '../stores/presentation/store_avatar.dart';
import 'grocery_theme.dart';

/// A product tile: photo, discount badge, name, unit, price (with the "was"
/// price struck through) and a ONE-TAP add button that turns into a quantity
/// stepper once the product is in the cart. Products with option groups
/// (rare for groceries) open the options sheet instead.
class GroceryProductCard extends ConsumerWidget {
  const GroceryProductCard({
    super.key,
    required this.token,
    required this.item,
    required this.s,
    this.width,
    this.fallbackGlyph = '🛒',
  });

  final String token;
  final MenuItem item;
  final Strings s;

  /// Shown instead of the photo when the product has none (its category's emoji).
  final String fallbackGlyph;

  /// Fixed width for the horizontal best-sellers strip; null fills a grid cell.
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartForStoreProvider(token));
    final qty = cart.lines.where((l) => l.item.id == item.id).fold<int>(0, (a, l) => a + l.quantity);
    final orderable = item.isOrderable;

    void add() {
      if (!orderable) return;
      if (item.optionGroups.isNotEmpty) {
        showItemSheet(context, storeToken: token, item: item, brand: Gr.accentDeep);
        return;
      }
      ref.read(cartProvider.notifier).add(
            token,
            CartLine(item: item, selectedOptionIds: const {}, quantity: 1),
          );
      AppHaptics.addedToCart();
    }

    void setQty(int q) {
      final line = cart.lines.where((l) => l.item.id == item.id && l.selectedOptionIds.isEmpty).firstOrNull;
      if (line == null) {
        if (q > 0) add();
        return;
      }
      AppHaptics.tick();
      ref.read(cartProvider.notifier).setQuantity(line.signature, q);
    }

    final card = Container(
      decoration: BoxDecoration(
        color: Gr.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Gr.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo with the discount badge in the start corner.
          AspectRatio(
            aspectRatio: 1.15,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColorFiltered(
                  colorFilter: orderable
                      ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                      : const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0.2126, 0.7152, 0.0722, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                  child: AppImage(
                    url: logoUrlOf(item.image),
                    placeholderColor: Gr.surface2,
                    error: ColoredBox(
                      color: Gr.surface2,
                      child: Center(child: Text(fallbackGlyph, style: const TextStyle(fontSize: 46))),
                    ),
                  ),
                ),
                if (item.hasDiscount)
                  PositionedDirectional(
                    top: 8,
                    start: 8,
                    child: _Badge(text: s.discountBadge(item.discountPercent!), color: Gr.accent, fg: Gr.onAccent),
                  ),
                if (!orderable)
                  PositionedDirectional(
                    bottom: 8,
                    start: 8,
                    child: _Badge(text: s.soldOut, color: Gr.red, fg: Colors.white),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Gr.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  item.unit ?? '',
                  maxLines: 1,
                  style: const TextStyle(fontSize: 12, color: Gr.ink3),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 6,
                        children: [
                          Text(
                            _money(item.price),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Gr.accent),
                          ),
                          if (item.compareAtPrice != null)
                            Text(
                              _money(item.compareAtPrice!),
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Gr.ink3,
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Gr.ink3,
                              ),
                            ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: AppMotion.dur(context, AppMotion.fast),
                      child: qty == 0
                          ? _AddButton(key: const ValueKey('add'), enabled: orderable, onTap: add)
                          : _Stepper(key: const ValueKey('stepper'), qty: qty, onChanged: setQty),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final sized = width == null ? card : SizedBox(width: width, child: card);

    return Semantics(
      button: true,
      label: '${item.name}, ${_money(item.price)}',
      child: GestureDetector(
        onTap: item.optionGroups.isNotEmpty ? add : null,
        behavior: HitTestBehavior.opaque,
        child: sized,
      ),
    );
  }

  static String _money(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, required this.fg});

  final String text;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({super.key, required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? Gr.accent : Gr.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.add_rounded, size: 20, color: enabled ? Gr.onAccent : Gr.ink3),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({super.key, required this.qty, required this.onChanged});

  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 28, height: 32, child: Icon(icon, size: 16, color: Gr.onAccent)),
        );

    return Container(
      decoration: BoxDecoration(color: Gr.accent, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, () => onChanged(qty - 1)),
          Text('$qty', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Gr.onAccent)),
          btn(Icons.add_rounded, () => onChanged(qty + 1)),
        ],
      ),
    );
  }
}
