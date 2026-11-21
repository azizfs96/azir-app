import 'package:flutter/material.dart';

/// The supermarket storefront's tokens: a white canvas, white outlined cards,
/// pale-green chips and inputs, dark type and one teal accent (clearly
/// distinct from the red sale prices).
///
/// Kept separate from `Ds` (the restaurant's warm cream system) so the two
/// verticals never bleed into each other.
abstract final class Gr {
  // Neutral whites and greys, sampled from the grocery-app reference: a pure
  // white canvas, white tiles with a barely-there grey edge, light-grey inputs
  // and chips, and neutral (not green-tinted) text greys.
  static const bg = Color(0xFFFFFFFF); // canvas
  static const surface = Color(0xFFFFFFFF); // cards, tiles
  static const surface2 = Color(0xFFF3F4F6); // chips, inputs, round buttons
  static const line = Color(0xFFEDEEF0); // hairlines, tile edges
  static const ink = Color(0xFF111827); // primary text
  static const ink2 = Color(0xFF4B5563); // secondary
  static const ink3 = Color(0xFF9CA3AF); // captions

  /// The soft lift under a product tile (reference: a faint shadow, no hard line).
  static const tileShadow = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 3)),
  ];
  static const accent = Color(0xFF0D9488); // teal — fills, links, hero accent
  static const accentDeep = Color(0xFF0F766E); // pressed / darker accents
  static const red = Color(0xFFE5484D);
  static const amber = Color(0xFFD9A21B);

  /// Text/icons on an accent fill.
  static const onAccent = Colors.white;

  /// The cart/checkout canvas keeps its pale green.
  static const cartCanvas = Color(0xFFEFF5F0);

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
  /// Measured from the grocery-app reference: 12pt margins, 12pt gutters.
  static const pageX = 12.0;

  /// The top bar sits a touch further in than the content (reference: ~16pt).
  static const headerX = 16.0;

  /// Corner radius of product tiles and cards (reference: ~12pt).
  static const cardRadius = 12.0;

  /// Columns on the home grid; the categories screen uses two.
  static const homeColumns = 3;

  /// Horizontal gap between product cards (the owner asked for tighter than
  /// the reference's 12).
  static const gutter = s8;

  /// Width of one home-grid cell for a screen of [screenWidth] — also the
  /// width of the best-sellers cards, so every product tile on the page is
  /// the same size.
  /// Not rounded: it must equal the width the grid itself hands each cell.
  static double homeCellWidth(double screenWidth) =>
      (screenWidth - pageX * 2 - gutter * (homeColumns - 1)) / homeColumns;
}
