import 'package:flutter/material.dart';

import '../../../core/localization/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/open_badge.dart';
import '../../stores/presentation/store_avatar.dart';
import '../data/my_stores_repository.dart';

/// ============================================================================
/// A STORE ROW ON THE HOME SCREEN (spec §5) — App Store "Top Free" layout.
///
///   ┌────┐  برجر بلد                    ┌────────┐
///   │LOGO│  مطعم برجر في العليا         │ إزالة  │
///   └────┘                              └────────┘
///   ────────────────────────────────────────────  (divider between rows)
///
/// The icon + text open the store; the "إزالة" pill removes it from the list.
/// Direction stays RTL: icon on the start (right), the button on the end (left).
/// ============================================================================
class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.store, required this.onTap, required this.onRemove});

  final MyStore store;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  /// iOS app-icon proportions.
  static const _iconSize = 72.0;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon + identity: the tap target that opens the store.
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  StoreAvatar(
                    name: store.name,
                    logoPath: store.logo,
                    brandColor: store.brandColor,
                    size: _iconSize,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                store.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink900,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            if (store.isOpen != null) ...[
                              const SizedBox(width: 8),
                              OpenBadge(open: store.isOpen!, s: s),
                            ],
                          ],
                        ),
                        if (store.description != null && store.description!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            store.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, color: AppColors.ink500, height: 1.35),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // "إزالة" — the App Store "Get"-style pill, tinted for a remove action.
        _RemovePill(label: s.removeStore, onTap: onRemove),
      ],
    );
  }
}

class _RemovePill extends StatelessWidget {
  const _RemovePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.ink100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.bad),
          ),
        ),
      ),
    );
  }
}
