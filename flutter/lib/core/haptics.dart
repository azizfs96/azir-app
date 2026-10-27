import 'package:flutter/services.dart';

/// Tactile feedback for the moments that should feel physical.
///
/// iOS honours the system "System Haptics" setting automatically, and on any
/// platform without a haptics engine (web, most desktops) these are silent
/// no-ops — so call sites never need to guard for platform.
abstract final class AppHaptics {
  /// A distinct thump the moment an item lands in the cart — the confirmation
  /// you feel without looking, the way most shopping apps do it.
  static void addedToCart() => HapticFeedback.heavyImpact();

  /// A light tap for incremental, repeatable controls: quantity steppers and
  /// option toggles. `lightImpact` (not the barely-there `selectionClick`) so it
  /// is actually felt, while staying gentle enough to fire many times in a row.
  static void tick() => HapticFeedback.lightImpact();

  /// A confirming thump when an order is successfully placed.
  static void success() => HapticFeedback.heavyImpact();
}
