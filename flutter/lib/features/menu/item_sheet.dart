import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/riyal_price.dart';
import '../stores/domain/menu.dart';
import '../stores/presentation/store_avatar.dart';
import 'cart_controller.dart';

/// ============================================================================
/// PICK OPTIONS AND ADD TO CART — the design system's product screen.
///
///   ┌──────────────────────────────┐
///   │ ⊗                            │  ← square photo, floating close
///   │           [ photo ]          │
///   ╭──────────────────────────────╮  ← body overlaps the photo by 30pt
///   │ اسم الصنف                    │     name 28/600, calories, description
///   │ 🔥 150 سعرة                  │
///   │ أضف مكونات          [اختياري]│  ← group head + required/optional pill
///   │ ┌──────────────────────────┐ │
///   │ │ ☐   ﷼+4      شوت إضافي  │ │  ← option rows: name · delta · check
///   │ │ ☐   ﷼+3      حليب لوز   │ │
///   │ └──────────────────────────┘ │
///   │ [ أضف للسلة  ﷼18 ] [ 🗑 1 + ]│  ← brand CTA + capsule quantity
///   ╰──────────────────────────────╯
///
/// Selection rules mirror the backend's own validation — a required
/// single-choice group must have exactly one pick before the dish can be
/// added, a multi group is capped at maxSelect.
/// ============================================================================
Future<void> showItemSheet(
  BuildContext context, {
  required String storeToken,
  required MenuItem item,
  required Color brand,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Ds.bg,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.95,
      child: _ItemSheet(storeToken: storeToken, item: item, brand: brand),
    ),
  );
}

class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({required this.storeToken, required this.item, required this.brand});

  final String storeToken;
  final MenuItem item;
  final Color brand;

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  /// Selected option ids per group id.
  final Map<int, Set<int>> _selected = {};
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    // A required single-choice group defaults to its first available option,
    // so the customer is never blocked by an unset radio they didn't notice.
    for (final group in widget.item.optionGroups) {
      if (group.isRequired && group.isSingleChoice) {
        final first = group.options.where((o) => o.isAvailable).firstOrNull;
        if (first != null) _selected[group.id] = {first.id};
      }
    }
  }

  bool get _isComplete => widget.item.optionGroups.every((group) {
        final chosen = _selected[group.id]?.length ?? 0;
        return chosen >= group.minSelect;
      });

  Set<int> get _allSelected => _selected.values.expand((s) => s).toSet();

  double get _unitPrice {
    var total = widget.item.price;
    for (final group in widget.item.optionGroups) {
      for (final option in group.options) {
        if (_allSelected.contains(option.id)) total += option.priceDelta;
      }
    }
    return total;
  }

  void _toggle(MenuOptionGroup group, MenuOption option) {
    if (!option.isAvailable) return;
    AppHaptics.tick();
    setState(() {
      final current = _selected[group.id] ?? <int>{};

      if (group.isSingleChoice) {
        _selected[group.id] = {option.id};
        return;
      }

      if (current.contains(option.id)) {
        current.remove(option.id);
      } else if (current.length < group.maxSelect) {
        current.add(option.id);
      }
      _selected[group.id] = current;
    });
  }

  void _add() {
    ref.read(cartProvider.notifier).add(
          widget.storeToken,
          CartLine(
            item: widget.item,
            selectedOptionIds: _allSelected,
            quantity: _quantity,
          ),
        );
    // A physical confirmation the moment it's in the cart.
    AppHaptics.addedToCart();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final item = widget.item;
    final brand = widget.brand;
    final imageUrl = logoUrlOf(item.image);
    final desc = item.description ?? '';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                return Stack(
                  children: [
                    // `.p-img`: a square hero on the soft fill.
                    SizedBox(
                      width: w,
                      height: w,
                      child: AppImage(
                        url: imageUrl,
                        fit: BoxFit.cover,
                        placeholderColor: Ds.soft,
                        error: const ColoredBox(
                          color: Ds.soft,
                          child: Center(child: Icon(Icons.restaurant_rounded, size: 54, color: Ds.ink3)),
                        ),
                      ),
                    ),
                    // `.p-body`: overlaps the photo by 30pt with its own rounded top.
                    Padding(
                      padding: EdgeInsets.only(top: w - 30),
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Ds.bg,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.name,
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.w600, height: 1.3, color: Ds.ink)),
                            if (item.calories != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.local_fire_department_rounded, size: 16, color: AppColors.flame),
                                  const SizedBox(width: 8),
                                  Text(s.caloriesLabel(item.calories!),
                                      style: const TextStyle(fontSize: 15, color: Ds.ink2)),
                                ],
                              ),
                            ],
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(desc, style: const TextStyle(fontSize: 14, height: 1.7, color: Ds.ink2)),
                            ],
                            for (final group in item.optionGroups)
                              _GroupBlock(
                                group: group,
                                selected: _selected[group.id] ?? const {},
                                brand: brand,
                                s: s,
                                onToggle: (option) => _toggle(group, option),
                              ),
                          ],
                        ),
                      ),
                    ),
                    // `.p-top`: the floating close button.
                    PositionedDirectional(
                      top: 14,
                      start: 16,
                      child: _RoundBtn(icon: Icons.close_rounded, onTap: () => Navigator.of(context).pop()),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // `.p-foot`: brand CTA (start) + capsule quantity (end), pinned.
        ColoredBox(
          color: Ds.bg,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: _Cta(
                      enabled: _isComplete,
                      brand: brand,
                      label: s.addToCart,
                      amount: _unitPrice * _quantity,
                      onTap: _add,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Qty(
                    quantity: _quantity,
                    brand: brand,
                    onChanged: (q) => setState(() => _quantity = q),
                    onRemove: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `.p-top .round`: a 44pt white round button with a soft drop shadow.
class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Ds.surface,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: Color(0x24000000), blurRadius: 12, offset: Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Icon(icon, size: 21, color: Ds.ink),
        ),
      ),
    );
  }
}

/// One option group: `.og-h` head (name + required/optional pill) and the
/// `.og` white card of option rows.
class _GroupBlock extends StatelessWidget {
  const _GroupBlock({
    required this.group,
    required this.selected,
    required this.brand,
    required this.s,
    required this.onToggle,
  });

  final MenuOptionGroup group;
  final Set<int> selected;
  final Color brand;
  final Strings s;
  final void Function(MenuOption) onToggle;

  @override
  Widget build(BuildContext context) {
    final isRequired = group.minSelect >= 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Ds.ink)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: isRequired ? brand.withValues(alpha: 0.10) : Ds.soft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(isRequired ? s.required : s.optional,
                    style: TextStyle(fontSize: 12, color: isRequired ? brand : Ds.ink3)),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(color: Ds.surface, borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < group.options.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: Ds.line),
                _OptionLine(
                  option: group.options[i],
                  selected: selected.contains(group.options[i].id),
                  brand: brand,
                  onTap: () => onToggle(group.options[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// `.oline`: name on the start, the price delta, then the check on the end.
class _OptionLine extends StatelessWidget {
  const _OptionLine({
    required this.option,
    required this.selected,
    required this.brand,
    required this.onTap,
  });

  final MenuOption option;
  final bool selected;
  final Color brand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final delta = option.priceDelta;
    return InkWell(
      onTap: option.isAvailable ? onTap : null,
      child: Opacity(
        opacity: option.isAvailable ? 1 : 0.4,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(option.name,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: Ds.ink)),
              ),
              if (delta != 0) ...[
                const SizedBox(width: 12),
                RiyalPrice(
                  amount: delta.abs(),
                  size: 14.5,
                  weight: FontWeight.w600,
                  color: selected ? Ds.ink : Ds.ink2,
                  sign: delta > 0 ? '+' : '−',
                ),
              ],
              const SizedBox(width: 12),
              _Check(selected: selected, brand: brand),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.ck`: a 24pt rounded square; brand-filled with a white check when on.
class _Check extends StatelessWidget {
  const _Check({required this.selected, required this.brand});
  final bool selected;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.dur(context, AppMotion.fast),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? brand : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: selected ? brand : Ds.ink3, width: 1.8),
      ),
      child: selected ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null,
    );
  }
}

/// `.qty`: the capsule stepper — trash at 1 (cancels), minus above, count, plus.
class _Qty extends StatelessWidget {
  const _Qty({
    required this.quantity,
    required this.brand,
    required this.onChanged,
    required this.onRemove,
  });

  final int quantity;
  final Color brand;
  final ValueChanged<int> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback onTap) => Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: () {
              AppHaptics.tick();
              onTap();
            },
            customBorder: const CircleBorder(),
            child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 20, color: brand)),
          ),
        );

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Ds.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: brand, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(quantity > 1 ? Icons.remove_rounded : Icons.delete_outline_rounded,
              () => quantity > 1 ? onChanged(quantity - 1) : onRemove()),
          const SizedBox(width: 6),
          SizedBox(
            width: 20,
            child: Text('$quantity',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Ds.ink)),
          ),
          const SizedBox(width: 6),
          btn(Icons.add_rounded, () => onChanged(quantity + 1)),
        ],
      ),
    );
  }
}

/// `.cta`: the brand "add to cart · price" capsule.
class _Cta extends StatelessWidget {
  const _Cta({
    required this.enabled,
    required this.brand,
    required this.label,
    required this.amount,
    required this.onTap,
  });

  final bool enabled;
  final Color brand;
  final String label;
  final double amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.8,
      child: Material(
        color: brand,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 58,
            // Scales the label down rather than ever overflowing on narrow phones.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Colors.white)),
                    const SizedBox(width: 10),
                    RiyalPrice(amount: amount, size: 17, weight: FontWeight.w600, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
