import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A price rendered the way the reference does: the amount followed by the new
/// Saudi Riyal symbol (U+20C0). Kept in one place so every screen shows money
/// identically, and so the glyph can be swapped for an asset in one edit.
class RiyalPrice extends StatelessWidget {
  const RiyalPrice({
    super.key,
    required this.amount,
    this.size = 15,
    this.color = AppColors.ink900,
    this.weight = FontWeight.w700,
    this.decimals = 0,
  });

  final double amount;
  final double size;
  final Color color;
  final FontWeight weight;
  final int decimals;

  // Currency label used app-wide for consistency. The 2024 Saudi Riyal symbol
  // has no glyph in the system fonts, so we use the standard "ر.س" everywhere;
  // swap this for the symbol once its font/SVG asset is bundled.
  static const riyalGlyph = 'ر.س';

  @override
  Widget build(BuildContext context) {
    final text = decimals == 0 && amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(decimals == 0 ? 2 : decimals);

    return Text('$text $riyalGlyph',
        textDirection: TextDirection.rtl,
        style: TextStyle(fontSize: size, fontWeight: weight, color: color));
  }
}
