import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/riyal_price.dart';
import '../stores/domain/menu.dart';
import '../stores/presentation/store_avatar.dart';
import 'cart_controller.dart';

/// ============================================================================
/// PICK OPTIONS AND ADD TO CART (RestaurantEngine, R2)
///
/// A bottom sheet for one dish: its photo, its option groups, a quantity
/// stepper, and a live-priced "add" button. Selection rules mirror the
/// backend's own validation — a required single-choice group must have exactly
/// one pick before the dish can be added, a multi group is capped at maxSelect.
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
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
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

  Set<int> get _allSelected =>
      _selected.values.expand((s) => s).toSet();

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
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final item = widget.item;
    final imageUrl = logoUrlOf(item.image);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // ---- image header with a close button -------------------------
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: SizedBox(
                      height: 240,
                      width: double.infinity,
                      child: imageUrl != null
                          ? Image.network(imageUrl, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _imagePlaceholder())
                          : _imagePlaceholder(),
                    ),
                  ),
                  PositionedDirectional(
                    top: 14,
                    start: 14,
                    child: _CircleBtn(
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink900)),
                    if (item.calories != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.local_fire_department_rounded,
                              size: 17, color: AppColors.flame),
                          const SizedBox(width: 4),
                          Text(s.caloriesLabel(item.calories!),
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink700)),
                        ],
                      ),
                    ],
                    if (item.description != null && item.description!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(item.description!,
                          style: const TextStyle(fontSize: 14.5, height: 1.55, color: AppColors.ink500)),
                    ],
                  ],
                ),
              ),

              for (final group in item.optionGroups)
                _GroupBlock(
                  group: group,
                  selected: _selected[group.id] ?? const {},
                  s: s,
                  onToggle: (option) => _toggle(group, option),
                ),

              const SizedBox(height: 12),
            ],
          ),
        ),

        // Quantity + add, pinned so they never scroll away.
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.ink100)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  _QuantityStepper(
                    quantity: _quantity,
                    onChanged: (q) => setState(() => _quantity = q),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isComplete ? _add : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ink900,
                        disabledBackgroundColor: AppColors.ink200,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(s.addToCart,
                                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            const Text('·', style: TextStyle(fontSize: 15, color: Colors.white)),
                            const SizedBox(width: 8),
                            RiyalPrice(
                                amount: _unitPrice * _quantity, size: 15, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imagePlaceholder() => ColoredBox(
        color: AppColors.cream,
        child: const Center(
            child: Icon(Icons.restaurant_rounded, size: 54, color: AppColors.ink300)),
      );
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, size: 22, color: AppColors.ink900),
          ),
        ),
      ),
    );
  }
}

class _GroupBlock extends StatelessWidget {
  const _GroupBlock({
    required this.group,
    required this.selected,
    required this.s,
    required this.onToggle,
  });

  final MenuOptionGroup group;
  final Set<int> selected;
  final Strings s;
  final void Function(MenuOption) onToggle;

  @override
  Widget build(BuildContext context) {
    final isRequired = group.minSelect >= 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section heading: name + a "required/optional" pill, as the reference.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Row(
            children: [
              Text(group.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink900)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.ink100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(isRequired ? s.required : s.optional,
                    style: const TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.ink500)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.ink100),
            ),
            child: Column(
              children: [
                for (var i = 0; i < group.options.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.ink100),
                  _OptionRow(
                    option: group.options[i],
                    selected: selected.contains(group.options[i].id),
                    single: group.isSingleChoice,
                    s: s,
                    onTap: () => onToggle(group.options[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.single,
    required this.s,
    required this.onTap,
  });

  final MenuOption option;
  final bool selected;
  final bool single;
  final Strings s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: option.isAvailable ? onTap : null,
      child: Opacity(
        opacity: option.isAvailable ? 1 : 0.4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          child: Row(
            children: [
              _Control(selected: selected, single: single),
              const SizedBox(width: 12),
              Expanded(
                child: Text(option.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink900)),
              ),
              if (option.priceDelta != 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(option.priceDelta > 0 ? '+' : '−',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink500)),
                    RiyalPrice(
                      amount: option.priceDelta.abs(),
                      size: 13.5,
                      color: AppColors.ink500,
                      weight: FontWeight.w600,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A Jahez-style radio (single) / checkbox (multi): a filled black mark when
/// selected, a hollow grey ring/box otherwise.
class _Control extends StatelessWidget {
  const _Control({required this.selected, required this.single});
  final bool selected;
  final bool single;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? AppColors.ink900 : Colors.transparent,
        shape: single ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: single ? null : BorderRadius.circular(7),
        border: selected ? null : Border.all(color: AppColors.ink300, width: 1.6),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : null,
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ink200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _StepButton(icon: Icons.remove_rounded, onTap: () => onChanged(quantity - 1)),
          SizedBox(
            width: 32,
            child: Text('$quantity',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          _StepButton(icon: Icons.add_rounded, onTap: () => onChanged(quantity + 1)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, size: 18, color: AppColors.ink700),
      ),
    );
  }
}
