import 'package:flutter/material.dart';

/// Design tokens (spec §32).
///
///   "Premium · Minimal · Modern · Clean · Professional"
///   "Avoid excessive gradients. Avoid excessive cards."
///
/// One neutral scale, one accent, semantic status colours. Surfaces are flat
/// with hairline borders; type and whitespace carry the hierarchy.
abstract final class AppColors {
  static const ink950 = Color(0xFF0A0A0B);
  static const ink900 = Color(0xFF141416);
  static const ink700 = Color(0xFF33333A);
  static const ink500 = Color(0xFF6B6B76);
  static const ink400 = Color(0xFF8E8E99);
  static const ink300 = Color(0xFFC4C4CC);
  static const ink200 = Color(0xFFE4E4E9);
  static const ink100 = Color(0xFFF1F1F4);
  static const ink50 = Color(0xFFF8F8FA);

  static const accent = Color(0xFF7C5CFF);
  static const accentSoft = Color(0xFFF2EEFF);

  // Restaurant vertical (Jahez-style): a warm cream canvas and an orange
  // "flame" used for calories and the best-sellers star — never the app's
  // purple accent, which does not belong in a food menu.
  static const cream = Color(0xFFF6F3EE);
  static const flame = Color(0xFFEF6C2E);

  static const ok = Color(0xFF0F7B5A);
  static const okSoft = Color(0xFFE7F6F0);
  static const warn = Color(0xFFA16207);
  static const warnSoft = Color(0xFFFDF6E3);
  static const bad = Color(0xFFB42318);
  static const badSoft = Color(0xFFFDECEB);
  static const info = Color(0xFF1D5FB8);
  static const infoSoft = Color(0xFFEAF1FC);
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// The bundled family (see pubspec.yaml).
///
/// It has to be repeated on every EXPLICIT TextStyle in this file: a TextStyle
/// supplied to a component theme is used as-is and does NOT inherit
/// ThemeData.fontFamily. That is why the app-bar title rendered in the system
/// font — and in a font with no Arabic coverage, as empty boxes.
const _fontFamily = 'IBMPlexSansArabic';

ThemeData buildAppTheme() {
  const base = ColorScheme.light(
    primary: AppColors.ink900,
    onPrimary: Colors.white,
    secondary: AppColors.accent,
    surface: Colors.white,
    onSurface: AppColors.ink900,
    error: AppColors.bad,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: AppColors.ink50,
    // A single family across Arabic and Latin keeps the product coherent when
    // a screen mixes both (spec §32).
    fontFamily: _fontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        color: AppColors.ink900,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: AppColors.ink900),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink900,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
          fontFamily: _fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink900,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.ink200),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.ink200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.ink200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.ink900, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.ink200, thickness: 1, space: 1),
  );
}
