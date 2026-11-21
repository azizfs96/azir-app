import 'package:flutter/material.dart';

/// The supermarket storefront's tokens: the pale-green canvas the cart uses,
/// white cards, dark type and one teal accent (fresh against the green canvas
/// and clearly distinct from the red sale prices).
///
/// Kept separate from `Ds` (the restaurant's warm cream system) so the two
/// verticals never bleed into each other.
abstract final class Gr {
  static const bg = Color(0xFFEFF5F0); // canvas — same as the cart page
  static const surface = Color(0xFFFFFFFF); // cards, tiles
  static const surface2 = Color(0xFFE2ECE5); // chips, inputs, round buttons
  static const line = Color(0xFFD8E3DB); // hairlines
  static const ink = Color(0xFF13231A); // primary text
  static const ink2 = Color(0xFF4F6457); // secondary
  static const ink3 = Color(0xFF8A9B91); // captions
  static const accent = Color(0xFF0D9488); // teal — fills, links, hero accent
  static const accentDeep = Color(0xFF0F766E); // pressed / darker accents
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFD9A21B);

  /// Text/icons on an accent fill.
  static const onAccent = Colors.white;

  /// The cart/checkout canvas (identical to [bg]; kept for call sites).
  static const cartCanvas = bg;
}
