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

  // Fixed heights of the text block so every card in a row is identical no
  // matter how long its name is or whether it has a unit / old price.
  static const _priceH = 20.0;
  static const _nameH = 34.0; // two lines of 12.5pt at 1.3
  static const _unitH = 16.0;

  /// Total height of a card whose square image tile is [width] wide:
  /// tile + 12 + price + 8 + name + 4 + unit.
  static double heightFor(double width) =>
      width + Gr.s12 + _priceH + Gr.s8 + _nameH + Gr.s4 + _unitH;

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
                  padding: const EdgeInsets.all(Gr.s12),
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
                  top: Gr.s8,
                  start: Gr.s8,
                  child: _Badge(text: s.discountBadge(item.discountPercent!), color: Gr.red),
                ),
              if (!orderable)
                PositionedDirectional(
                  top: Gr.s8,
                  end: Gr.s8,
                  child: _Badge(text: s.soldOut, color: AppColors.ink700),
                ),
              // "+" in the end corner — the one tap that adds; a stepper after.
              PositionedDirectional(
                bottom: Gr.s8,
                end: Gr.s8,
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
        const SizedBox(height: Gr.s12),
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
                  size: 14.5,
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
        const SizedBox(height: Gr.s8),
        SizedBox(
          height: _nameH,
          child: Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Gr.ink, height: 1.3),
          ),
        ),
        const SizedBox(height: Gr.s4),
        // Always reserved, so cards without a unit stay the same height.
        SizedBox(
          height: _unitH,
          child: (item.unit ?? '').isEmpty
              ? null
              : Text(
                  item.unit!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Gr.ink3, height: 1.3),
                ),
        ),
      ],
    );

    final sized = width == null ? card : SizedBox(width: width, height: heightFor(width!), child: card);

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
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
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
    return Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: Gr.line)),
      elevation: 1.5,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.add_rounded, size: 20, color: enabled ? AppColors.ink900 : AppColors.ink300),
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
          child: SizedBox(width: 28, height: 32, child: Icon(icon, size: 16, color: Gr.onAccent)),
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
