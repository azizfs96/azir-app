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

  // --- Spacing: an 8pt grid. Every gap in the grocery screens is one of these.
  static const s4 = 4.0; // fine adjustments (name → unit)
  static const s8 = 8.0; // related elements (price → name, icon → label)
  static const s12 = 12.0; // inside a group (tile → price, card padding, gutters)
  static const s16 = 16.0; // between elements and cards (title → products)
  static const s24 = 24.0; // inner margins, header → search → categories
  static const s32 = 32.0; // between sections
  static const s40 = 40.0; // between major content groups
  static const s48 = 48.0; // large breathing room

  /// Horizontal page margin, identical on both edges of every screen.
  static const pageX = 20.0;

  /// Corner radius of product tiles and large cards.
  static const cardRadius = 20.0;

  /// Columns on the home grid; the categories screen uses two.
  static const homeColumns = 3;

  /// Width of one home-grid cell for a screen of [screenWidth] — also the
  /// width of the best-sellers cards, so every product tile on the page is
  /// the same size.
  /// Not rounded: it must equal the width the grid itself hands each cell.
  static double homeCellWidth(double screenWidth) =>
      (screenWidth - pageX * 2 - s12 * (homeColumns - 1)) / homeColumns;
}
