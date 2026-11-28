import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The supermarket template's design system, taken from the owner's Figma
/// file ("Supermarket – Home v3 (Attractive)", Categories, Category, Search):
///
///   * canvas #F6F7F4, white cards with soft green-tinted shadows
///   * one dark forest green (#0E3B2E) for buttons, the tab bar and the add
///     controls, and a lime (#D4F36A) for the active tab, tags and badges
///   * pills everywhere (radius 999), 24/18/20/10 radii on cards and tiles
///   * the Cairo typeface
///
/// Kept separate from `Ds` (the restaurant system) so the two verticals never
/// bleed into each other.
abstract final class Gr {
  // --- colour -------------------------------------------------------------
  static const bg = Color(0xFFF6F7F4); // page canvas
  static const surface = Color(0xFFFFFFFF); // cards, pills, tiles
  static const surface2 = Color(0xFFEDF0ED); // dividers, inactive rank chips
  static const line = Color(0xFFEDF0ED);
  static const ink = Color(0xFF0B0F0C); // primary text
  static const ink2 = Color(0xFF737875); // secondary (greeting, "see all")
  static const ink3 = Color(0xFF8C918F); // captions, units, placeholders
  static const primary = Color(0xFF0E3B2E); // dark green
  static const lime = Color(0xFFD4F36A);
  static const onPrimary = Colors.white;
  static const onLime = primary;
  static const red = Color(0xFFE5484D); // only for "sold out" / errors

  /// Legacy names still used by the shared cart / order screens.
  static const accent = primary;
  static const accentDeep = primary;
  static const onAccent = onPrimary;
  static const cartCanvas = bg;

  // --- shadows (all green-tinted black, rgba(13,31,23,…)) -----------------
  static const _shadowInk = Color(0xFF0D1F17);
  static List<BoxShadow> shadow(double y, double blur, double alpha) => [
        BoxShadow(color: _shadowInk.withValues(alpha: alpha), offset: Offset(0, y), blurRadius: blur),
      ];
  static final cardShadow = shadow(6, 18, 0.06); // product / category cards
  static final tileShadow = shadow(6, 14, 0.10); // 64pt category tiles
  static final pillShadow = shadow(4, 12, 0.05); // top-bar pills & circles
  static final chipShadow = shadow(3, 10, 0.04); // filter chips
  static final searchShadow = shadow(6, 20, 0.06);
  static final heroShadow = shadow(14, 30, 0.18);
  static final barShadow = shadow(12, 32, 0.28); // floating tab bar / cart bar

  // --- geometry -----------------------------------------------------------
  static const pageX = 20.0; // content inset on every screen
  static const pill = 999.0;
  static const rCardMinimal = 24.0; // 2-column product image
  static const rCardCompact = 18.0; // 3-column product image
  static const rCategoryCard = 20.0; // categories-page photo
  static const rCategoryTile = 10.0; // home 64pt tile
  static const rHero = 28.0;
  static const tabBarHeight = 68.0;
  static const cartBarHeight = 64.0;

  // --- type (Cairo) -------------------------------------------------------
  static const fontFamily = 'Cairo';

  /// Cairo at [size]/[weight]. The family ships as a variable font, so the
  /// `wght` axis is set alongside `fontWeight` for engines that need it.
  static TextStyle text(
    double size, {
    int weight = 400,
    Color color = ink,
    double? height,
    TextDecoration? decoration,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: _weight(weight),
        fontVariations: [FontVariation('wght', weight.toDouble())],
        color: color,
        height: height,
        decoration: decoration,
        decorationColor: color,
      );

  static FontWeight _weight(int w) => switch (w) {
        <= 400 => FontWeight.w400,
        500 => FontWeight.w500,
        600 => FontWeight.w600,
        700 => FontWeight.w700,
        _ => FontWeight.w800,
      };

  /// "9.50 ر.س" — the design prints the currency as text after the amount.
  static String price(double amount, String sar) => '${amount.toStringAsFixed(2)} $sar';
}

/// One of the stroke icons exported from the Figma design
/// (`assets/icons/grocery/<name>.svg`). [color] re-tints every stroke.
class GrIcon extends StatelessWidget {
  const GrIcon(this.name, {super.key, required this.size, this.color, this.flipForRtl = false});

  final String name;
  final double size;
  final Color? color;

  /// Directional glyphs (arrows) point "forward" in the asset's LTR frame.
  final bool flipForRtl;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final icon = SvgPicture.asset(
      'assets/icons/grocery/$name.svg',
      width: size,
      height: size,
      colorFilter: color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
    );
    return flipForRtl && rtl ? Transform.flip(flipX: true, child: icon) : icon;
  }
}
