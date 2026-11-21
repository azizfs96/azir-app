import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/riyal_price.dart';
import '../menu/cart_controller.dart';
import '../menu/item_sheet.dart';
import '../stores/domain/menu.dart';
import '../stores/presentation/store_avatar.dart';
import 'grocery_theme.dart';

/// A product tile in the grocery-app idiom (the reference screenshot):
///
///   ┌──────────────┐
///   │   product    │   a light square image tile, the discount badge in the
///   │    photo   + │   start corner, a small "+" in the end corner that turns
///   └──────────────┘   into a quantity stepper once the product is in the cart
///   ﷼ 29.95  ~~34.50~~  sale price in red with the old price struck through
///   راتشيلز زبادي يوناني   the name, two lines, then the unit
///
/// Compact enough for THREE columns on the home page; the same tile simply
/// grows in the two-column categories screen. Products with option groups
/// (rare for groceries) open the options sheet instead of adding directly.
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

  /// Fixed width for the horizontal best-sellers strip; null fills a grid cell.
  final double? width;

  /// Shown instead of the photo when the product has none (its category's emoji).
  final String fallbackGlyph;

  static const _priceH = 20.0;
  static const _nameStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Gr.ink, height: 1.35);
  // Text lines are budgeted at their rounded-up height (13 × 1.35 = 17.55 →
  // 18; 11 × 1.25 = 13.75 → 14): the engine snaps line boxes up, so an exact
  // product would overflow by a fraction of a pixel.
  static const _nameLineH = 18.0;
  static const _unitH = 2.0 + 14.0;

  /// Total height of a card whose square image tile is [width] wide and whose
  /// name needs [nameLines] lines: tile + 8 + price + 4 + name + unit, plus
  /// one pixel of slack for device-pixel rounding.
  /// Grids pass the result of [nameLinesFor] so a section of one-line names
  /// does not reserve an empty second line under every card.
  static double heightFor(double width, {int nameLines = 1}) =>
      (width + Gr.s8 + _priceH + Gr.s4 + _nameLineH * nameLines + _unitH).ceilToDouble() + 1;

  /// 1 when every name in [items] fits one line at [width], else 2 — measured
  /// with the card's own text style and the ambient text scale.
  static int nameLinesFor(BuildContext context, Iterable<MenuItem> items, double width) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    );
    for (final item in items) {
      painter.text = TextSpan(text: item.name, style: _nameStyle);
      painter.layout(maxWidth: width);
      if (painter.computeLineMetrics().length > 1) {
        painter.dispose();
        return 2;
      }
    }
    painter.dispose();
    return 1;
  }

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

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The image tile: light so product packaging reads like the reference.
        AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Gr.surface,
                  borderRadius: BorderRadius.circular(Gr.cardRadius),
                  border: Border.all(color: Gr.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(Gr.s8),
                  child: ColorFiltered(
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
                      fit: BoxFit.contain,
                      placeholderColor: Colors.transparent,
                      error: Center(child: Text(fallbackGlyph, style: const TextStyle(fontSize: 44))),
                    ),
                  ),
                ),
              ),
              if (item.hasDiscount)
                PositionedDirectional(
                  top: 6,
                  start: 6,
                  child: _Badge(text: s.discountBadge(item.discountPercent!), color: Gr.red),
                ),
              if (!orderable)
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: _Badge(text: s.soldOut, color: AppColors.ink700),
                ),
              // "+" in the end corner — the one tap that adds; a stepper after.
              PositionedDirectional(
                bottom: 6,
                end: 6,
                child: AnimatedSwitcher(
                  duration: AppMotion.dur(context, AppMotion.fast),
                  child: qty == 0
                      ? _AddButton(key: const ValueKey('add'), enabled: orderable, onTap: add)
                      : _Stepper(key: const ValueKey('stepper'), qty: qty, onChanged: setQty),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gr.s8),
        // Price line: sale price in red, old price struck through. Scales down
        // rather than overflowing in a narrow three-column cell.
        SizedBox(
          height: _priceH,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RiyalPrice(
                  amount: item.price,
                  size: 15,
                  weight: FontWeight.w800,
                  color: item.hasDiscount ? Gr.red : Gr.ink,
                  decimals: 2,
                ),
                if (item.compareAtPrice != null) ...[
                  const SizedBox(width: 6),
                  const SarGlyph(size: 9, color: Gr.ink3),
                  const SizedBox(width: 2),
                  Text(
                    item.compareAtPrice!.toStringAsFixed(2),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Gr.ink3,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Gr.ink3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: Gr.s4),
        // The name takes its natural height (one or two lines) and the unit
        // sits directly under it; the row height is fixed by the grid, so any
        // slack ends up below the card instead of between name and unit.
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _nameStyle,
        ),
        if ((item.unit ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            item.unit!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Gr.ink3, height: 1.25),
          ),
        ],
      ],
    );

    // In the horizontal strip the parent fixes the height; here only the width.
    final sized = width == null ? card : SizedBox(width: width, child: card);

    return Semantics(
      button: true,
      label: '${item.name}, ${item.price}',
      child: GestureDetector(
        onTap: item.optionGroups.isNotEmpty ? add : null,
        behavior: HitTestBehavior.opaque,
        child: sized,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Gr.s8)),
      child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
    );
  }
}

/// The small "+" that sits on the image tile (reference: a thin plus in the corner).
class _AddButton extends StatelessWidget {
  const _AddButton({super.key, required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Reference: a plain white disc with a soft shadow, no outline.
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: Colors.black38,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(Icons.add_rounded, size: 18, color: enabled ? AppColors.ink900 : AppColors.ink300),
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
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(width: 26, height: 28, child: Icon(icon, size: 15, color: Gr.onAccent)),
        );

    return Material(
      color: Gr.accent,
      borderRadius: BorderRadius.circular(99),
      elevation: 1.5,
      shadowColor: Colors.black26,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, () => onChanged(qty - 1)),
          Text('$qty', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Gr.onAccent)),
          btn(Icons.add_rounded, () => onChanged(qty + 1)),
        ],
      ),
    );
  }
}
