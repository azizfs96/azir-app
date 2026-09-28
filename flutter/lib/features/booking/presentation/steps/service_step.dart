import 'package:flutter/material.dart';

import '../../../../core/localization/strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../stores/domain/storefront.dart';

/// ============================================================================
/// CHOOSE A SERVICE — the first real decision in the booking flow (spec §41)
///
///   اختر الخدمة
///   [ الكل ]  [ الشعر ]  [ البشرة ]        ← only when grouping exists
///
///   ┌──────────────────────────────────┐
///   │ ✂  قص شعر                100 ر.س  │
///   │    ٣٠ دقيقة                       │
///   └──────────────────────────────────┘
///
/// This screen replaced a generic three-way picker shared with staff and
/// branch. Choosing a service is not the same interaction: a customer is
/// comparing PRICE and DURATION against each other, so both have to be
/// scannable down a column rather than buried in a subtitle.
/// ============================================================================
class ServiceStep extends StatefulWidget {
  const ServiceStep({
    super.key,
    required this.store,
    required this.s,
    required this.brand,
    required this.selected,
    required this.onSelected,
  });

  final Storefront store;
  final Strings s;
  final Color brand;
  final StoreService? selected;
  final ValueChanged<StoreService> onSelected;

  @override
  State<ServiceStep> createState() => _ServiceStepState();
}

class _ServiceStepState extends State<ServiceStep> {
  /// null = "all"; otherwise the chosen category id.
  int? _categoryId;

  List<StoreService> get _visible {
    if (_categoryId == null) return widget.store.services;

    final category = widget.store.categories
        .where((c) => c.id == _categoryId)
        .firstOrNull;

    return category?.services ?? widget.store.services;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final services = _visible;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          s.chooseService,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.ink900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          s.chooseServiceHint,
          style: const TextStyle(fontSize: 14, color: AppColors.ink500),
        ),

        // Filters appear only when the merchant actually grouped services —
        // a lone "All" chip would be a control that does nothing.
        if (widget.store.hasCategories) ...[
          const SizedBox(height: 18),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _CategoryChip(
                  label: s.allServices,
                  selected: _categoryId == null,
                  brand: widget.brand,
                  onTap: () => setState(() => _categoryId = null),
                ),
                for (final category in widget.store.categories)
                  _CategoryChip(
                    label: category.name,
                    selected: _categoryId == category.id,
                    brand: widget.brand,
                    onTap: () => setState(() => _categoryId = category.id),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 18),

        if (services.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                s.noServices,
                style: const TextStyle(fontSize: 14, color: AppColors.ink500),
              ),
            ),
          )
        else
          for (final service in services) ...[
            _ServiceCard(
              service: service,
              s: s,
              brand: widget.brand,
              selected: service.id == widget.selected?.id,
              onTap: () => widget.onSelected(service),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.brand,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color brand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Material(
        color: selected ? brand : AppColors.ink100,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.ink700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.s,
    required this.brand,
    required this.selected,
    required this.onTap,
  });

  final StoreService service;
  final Strings s;
  final Color brand;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            // Selection reads as a tinted, brand-bordered card rather than a
            // checkbox — the whole row is the target, so the whole row responds.
            color: selected ? brand.withValues(alpha: 0.05) : Colors.white,
            border: Border.all(
              color: selected ? brand : AppColors.ink200,
              width: selected ? 1.6 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: brand.withValues(alpha: selected ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.content_cut_rounded, size: 19, color: brand),
              ),
              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      service.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: AppColors.ink900,
                      ),
                    ),
                    if (service.description != null &&
                        service.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        service.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.ink500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Duration as a chip, not a subtitle: it is the second
                    // thing being compared, so it needs its own weight.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.ink100,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 12, color: AppColors.ink500),
                          const SizedBox(width: 4),
                          Text(
                            s.minutes(service.durationMinutes),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _money(service.price),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    s.currency,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.ink400),
                  ),
                  if (selected) ...[
                    const SizedBox(height: 8),
                    Icon(Icons.check_circle_rounded, size: 19, color: brand),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _money(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}
