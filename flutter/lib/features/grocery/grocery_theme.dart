import 'package:flutter/material.dart';

/// The supermarket storefront's tokens: a deep-green canvas with lifted dark
/// cards, white type and one fresh-green accent (the design reference).
///
/// Kept separate from `Ds` (the restaurant's warm cream system) and from the
/// app theme — this vertical paints dark surfaces inside the light app theme.
abstract final class Gr {
  static const bg = Color(0xFF0C1A12); // canvas
  static const surface = Color(0xFF14241A); // cards
  static const surface2 = Color(0xFF1B3024); // chips, thumbs, inputs
  static const line = Color(0xFF26402F); // hairlines
  static const ink = Color(0xFFF4F7F5); // primary text
  static const ink2 = Color(0xFFA9BBB0); // secondary
  static const ink3 = Color(0xFF6F8577); // captions
  static const accent = Color(0xFF3DDC84); // fresh green
  static const accentDeep = Color(0xFF1F8F4E); // pressed / badges on light
  static const red = Color(0xFFF26B5B);
  static const amber = Color(0xFFF5B942);

  /// Dark-on-accent text (the accent is light enough for black type).
  static const onAccent = Color(0xFF07140C);

  /// Ink for the light cart/checkout surfaces this vertical reuses.
  static const cartCanvas = Color(0xFFEFF5F0);
}
