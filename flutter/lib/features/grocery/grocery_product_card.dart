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

/// Which of the design's two product cards to draw.
enum GroceryCardStyle {
  /// "Product Card – Minimal" (Figma 10:239): 2-column, image 175 tall with
  /// 24pt corners, name 15, unit 12, price 16 + a 34pt round add button.
  minimal,

  /// "Product Card – Compact" (Figma 20:358): 3-column, square image with
  /// 18pt corners, name 13, unit 11, price 13 + a 34pt rounded-square add.
  compact,
}

/// A product card in the design's idiom. The one tap on the add button puts
/// the product in the cart (no sheet, unless it has option groups); once in
/// the cart the button becomes a − qty + pill in the same dark green.
class GroceryProductCard extends ConsumerWidget {
  const GroceryProductCard({
    super.key,
    required this.token,
    required this.item,
    required this.s,
    this.style = GroceryCardStyle.minimal,
    this.width,
    this.fallbackGlyph = '🛒',
  });

  final String token;
  final MenuItem item;
  final Strings s;
  final GroceryCardStyle style;

  /// Fixed width for horizontal strips; null fills a grid cell.
  final double? width;

  /// Shown instead of the photo when the product has none (its category's emoji).
  final String fallbackGlyph;

  bool get _minimal => style == GroceryCardStyle.minimal;

  /// Height of a card in a grid whose cells are [cellWidth] wide:
  /// image + gap + name + unit + gap + price row.
  static double heightFor(double cellWidth, GroceryCardStyle style) {
    final minimal = style == GroceryCardStyle.minimal;
    final image = minimal ? 175.0 : cellWidth;
    final gap = minimal ? 8.0 : 6.0;
    final name = (minimal ? 15.0 : 13.0) * 1.25;
    final unit = (minimal ? 12.0 : 11.0) * 1.25;
    return image + gap + name + unit + gap + 34 + 2;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartForStoreProvider(token));
    final qty = cart.lines.where((l) => l.item.id == item.id).fold<int>(0, (a, l) => a + l.quantity);
    final orderable = item.isOrderable;

    void add() {
      if (!orderable) return;
      if (item.optionGroups.isNotEmpty) {
        showItemSheet(context, storeToken: token, item: item, brand: Gr.primary);
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

    final imageRadius = _minimal ? Gr.rCardMinimal : Gr.rCardCompact;
    final textPad = _minimal ? 4.0 : 2.0;

    Widget image(double? height) => Container(
          height: height,
          decoration: BoxDecoration(
            color: Gr.surface,
            borderRadius: BorderRadius.circular(imageRadius),
            boxShadow: Gr.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
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
                  fit: BoxFit.cover,
                  placeholderColor: Gr.surface,
                  error: Center(
                    child: Text(fallbackGlyph, style: TextStyle(fontSize: _minimal ? 64 : 44)),
                  ),
                ),
              ),
              if (!orderable)
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: _Badge(text: s.soldOut, color: AppColors.ink700),
                ),
              if (item.hasDiscount && orderable)
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: _Badge(text: '-${item.discountPercent}%', color: Gr.lime, textColor: Gr.onLime),
                ),
            ],
          ),
        );

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_minimal) image(175) else AspectRatio(aspectRatio: 1, child: image(null)),
        SizedBox(height: _minimal ? 8 : 6),
        Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: textPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Gr.text(_minimal ? 15 : 13, weight: 600, height: 1.25),
              ),
              Text(
                (item.unit ?? '').isEmpty ? ' ' : item.unit!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Gr.text(_minimal ? 12 : 11, color: Gr.ink3, height: 1.25),
              ),
            ],
          ),
        ),
        SizedBox(height: _minimal ? 8 : 6),
        Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: textPad),
          child: Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        Gr.price(item.price, s.sar),
                        style: Gr.text(_minimal ? 16 : 13, weight: 700, height: 1.25),
                      ),
                      if (item.compareAtPrice != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          item.compareAtPrice!.toStringAsFixed(2),
                          style: Gr.text(_minimal ? 12 : 11, color: Gr.ink3, decoration: TextDecoration.lineThrough),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: AppMotion.dur(context, AppMotion.fast),
                child: qty == 0
                    ? _AddButton(
                        key: const ValueKey('add'),
                        enabled: orderable,
                        radius: _minimal ? 17 : 14,
                        onTap: add,
                      )
                    : _Stepper(key: const ValueKey('stepper'), qty: qty, onChanged: setQty),
              ),
            ],
          ),
        ),
      ],
    );

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
  const _Badge({required this.text, required this.color, this.textColor = Colors.white});

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Gr.pill)),
      // LTR so "-14%" keeps its sign in front inside an RTL layout.
      child: Text(text, textDirection: TextDirection.ltr, style: Gr.text(11, weight: 700, color: textColor)),
    );
  }
}

/// The 34pt dark-green add control (round on the minimal card, 14pt-rounded
/// square on the compact card), with the design's white "+" stroke.
class _AddButton extends StatelessWidget {
  const _AddButton({super.key, required this.enabled, required this.radius, required this.onTap});

  final bool enabled;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? Gr.primary : Gr.surface2,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Center(
            child: enabled
                ? const GrIcon('plus', size: 16)
                : const Icon(Icons.add_rounded, size: 18, color: Gr.ink3),
          ),
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
          borderRadius: BorderRadius.circular(Gr.pill),
          child: SizedBox(width: 30, height: 34, child: Icon(icon, size: 16, color: Gr.onPrimary)),
        );

    return Material(
      color: Gr.primary,
      borderRadius: BorderRadius.circular(Gr.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, () => onChanged(qty - 1)),
          Text('$qty', style: Gr.text(13, weight: 800, color: Gr.onPrimary)),
          btn(Icons.add_rounded, () => onChanged(qty + 1)),
        ],
      ),
    );
  }
}
