import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A network image with a calm, reserved load: a neutral placeholder fills the
/// (already-bounded) slot while bytes arrive, then the decoded image cross-fades
/// in — no white flash, no hard pop, no layout shift. Falls back to [error] when
/// there is no URL or the load fails.
///
/// Zero dependencies: it relies on Flutter's in-memory ImageCache (repeat views
/// within a session are instant). Disk caching / BlurHash placeholders are a
/// later enhancement that needs backend support.
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.error,
    this.placeholderColor,
  });

  final String? url;
  final BoxFit fit;

  /// Shown when there is no URL or the image fails to load.
  final Widget? error;

  /// The holding colour while the image decodes. Defaults to a warm neutral.
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    final bg = placeholderColor ?? AppColors.ink100;
    final fallback = error ??
        const Center(child: Icon(Icons.restaurant_rounded, size: 28, color: AppColors.ink300));

    final u = url;
    if (u == null || u.isEmpty) return _fill(bg, fallback);

    return Image.network(
      u,
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child; // already in memory cache
        return AnimatedSwitcher(
          duration: AppMotion.dur(context, AppMotion.base),
          switchInCurve: Curves.easeOut,
          child: frame == null ? _fill(bg, null) : child,
        );
      },
      errorBuilder: (_, _, _) => _fill(bg, fallback),
    );
  }

  Widget _fill(Color bg, Widget? child) =>
      Container(color: bg, alignment: Alignment.center, child: child);
}
