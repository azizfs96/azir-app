import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design tokens — the Azir identity is black and white; status colours are
/// the only chroma. Flat surfaces, hairline borders, type carries hierarchy.
abstract final class AppColors {
  static const bg = Color(0xFFF5F5F7); // page canvas
  static const surface = Color(0xFFFFFFFF); // cards, inputs
  static const soft = Color(0xFFEFEFF2); // subtle fills, thumbs
  static const ink = Color(0xFF0A0A0B); // primary text, primary button
  static const ink2 = Color(0xFF5E5E66); // secondary text
  static const ink3 = Color(0xFF9A9AA3); // captions, hints
  static const line = Color(0xFFE6E6EA); // hairline borders

  static const ok = Color(0xFF0F7B5A);
  static const okSoft = Color(0xFFE7F6F0);
  static const warn = Color(0xFFA16207);
  static const warnSoft = Color(0xFFFDF6E3);
  static const bad = Color(0xFFB42318);
  static const badSoft = Color(0xFFFDECEB);
  static const info = Color(0xFF1D5FB8);
  static const infoSoft = Color(0xFFEAF1FC);
}

/// Motion: short and calm. Every duration goes through [dur] so the OS
/// "reduce motion" setting collapses it to an instant change.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  static Duration dur(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

abstract final class AppHaptics {
  /// An order was claimed / a leg of the delivery was confirmed.
  static void success() => HapticFeedback.heavyImpact();

  static void tick() => HapticFeedback.lightImpact();
}

ThemeData buildAppTheme() {
  const radius = 14.0;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: AppColors.ink,
      onPrimary: Colors.white,
      secondary: AppColors.ink2,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.bad,
      outline: AppColors.line,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w800),
      iconTheme: IconThemeData(color: AppColors.ink),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: AppColors.ink3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.bad),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.ink,
      unselectedLabelColor: AppColors.ink3,
      indicatorColor: AppColors.ink,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.line,
      labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
