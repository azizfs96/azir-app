import 'package:flutter/material.dart';

import '../localization/strings.dart';
import '../theme/app_theme.dart';

/// A small "مفتوح / مغلق" pill: green when the store is open, red when closed —
/// shown next to the store name (home list + storefront header).
class OpenBadge extends StatelessWidget {
  const OpenBadge({super.key, required this.open, required this.s, this.compact = false});

  final bool open;
  final Strings s;

  /// A denser variant for tight rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = open ? AppColors.ok : AppColors.bad;
    final bg = open ? AppColors.okSoft : AppColors.badSoft;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(
            open ? s.storeOpen : s.storeClosed,
            style: TextStyle(fontSize: compact ? 11 : 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
