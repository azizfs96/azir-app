import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// A generic "choose one" step.
///
/// Service, staff and branch are the same interaction with different data, so
/// they share one widget rather than three near-identical screens.
class PickerStep<T> extends StatelessWidget {
  const PickerStep({
    super.key,
    required this.title,
    required this.items,
    required this.labelOf,
    required this.onSelected,
    this.selected,
    this.subtitleOf,
    this.trailingOf,
    this.anyOptionLabel,
    this.onAnySelected,
  });

  final String title;
  final List<T> items;
  final T? selected;
  final String Function(T) labelOf;
  final String? Function(T)? subtitleOf;
  final String? Function(T)? trailingOf;
  final void Function(T) onSelected;

  /// "Any available staff" — a real choice, not the absence of one (spec §9).
  final String? anyOptionLabel;
  final VoidCallback? onAnySelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.ink900,
          ),
        ),
        const SizedBox(height: 20),

        if (anyOptionLabel != null) ...[
          _Tile(
            label: anyOptionLabel!,
            selected: false,
            onTap: onAnySelected ?? () {},
          ),
          const SizedBox(height: 10),
        ],

        for (final item in items) ...[
          _Tile(
            label: labelOf(item),
            subtitle: subtitleOf?.call(item),
            trailing: trailingOf?.call(item),
            selected: item == selected,
            onTap: () => onSelected(item),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String label;
  final String? subtitle;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.ink900 : AppColors.ink200,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink900,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: const TextStyle(fontSize: 13, color: AppColors.ink400),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink900,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
