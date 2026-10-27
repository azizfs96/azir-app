import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_theme.dart';
import 'sar_glyph.dart';

/// A price rendered the way the design system does it: the Saudi Riyal symbol
/// then the amount, as one LTR-isolated unit (`.money`), so it never flips or
/// splits inside Arabic text. Kept in one place so every screen shows money
/// identically.
class RiyalPrice extends StatelessWidget {
  const RiyalPrice({
    super.key,
    required this.amount,
    this.size = 15,
    this.color = Ds.ink,
    this.weight = FontWeight.w700,
    this.decimals = 0,
    this.sign = '',
  });

  final double amount;
  final double size;
  final Color color;
  final FontWeight weight;
  final int decimals;

  /// An optional leading sign for deltas ("+" / "−"), kept inside the LTR unit.
  final String sign;

  /// Plain-text fallback label, for places that cannot render the glyph.
  static const riyalGlyph = 'ر.س';

  @override
  Widget build(BuildContext context) {
    final text = decimals == 0 && amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(decimals == 0 ? 2 : decimals);

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SarGlyph(size: size * 0.9, color: color),
        SizedBox(width: size * 0.22),
        Text('$sign$text',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: size, fontWeight: weight, color: color, height: 1.15)),
      ],
    );
  }
}

/// The Riyal symbol on its own (e.g. beside a "+" delta price).
class SarGlyph extends StatelessWidget {
  const SarGlyph({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
        sarGlyphSvg,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}
