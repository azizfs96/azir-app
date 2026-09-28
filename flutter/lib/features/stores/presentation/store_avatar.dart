import 'package:flutter/material.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/app_theme.dart';

/// Parse a merchant's `#RRGGBB` into a Color, falling back to ink.
///
/// Shared so the home card, the storefront header and anything else that paints
/// with a merchant's identity agree on the same value.
Color brandColorOf(String? hex) {
  final cleaned = hex?.replaceFirst('#', '');
  if (cleaned == null || cleaned.length != 6) return AppColors.ink900;

  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? AppColors.ink900 : Color(0xFF000000 | value);
}

/// Resolve a stored logo path to an absolute URL.
String? logoUrlOf(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return path;

  // Env.apiBase ends in /api/v1; storage is served from the site root.
  final origin = Env.apiBase.replaceFirst(RegExp(r'/api/v\d+/?$'), '');
  return '$origin/storage/$path';
}

/// ============================================================================
/// A MERCHANT'S LOGO, RENDERED AS AN APP ICON
///
/// Rounded square at iOS app-icon proportions — the shape people already read
/// as "a brand I chose to keep". Used on the home cards and the storefront
/// header so a merchant looks like the same business in both places.
///
/// A store without a logo gets a monogram on its brand colour rather than a
/// broken-image box, so it still reads as a brand.
/// ============================================================================
class StoreAvatar extends StatelessWidget {
  const StoreAvatar({
    super.key,
    required this.name,
    required this.logoPath,
    required this.brandColor,
    this.size = 60,
    this.inverted = false,
  });

  final String name;
  final String? logoPath;
  final String? brandColor;
  final double size;

  /// When the avatar sits ON the brand colour, a same-colour monogram would
  /// vanish — so invert to a white tile with the brand colour as the letter.
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final url = logoUrlOf(logoPath);
    final brand = brandColorOf(brandColor);

    // iOS app icons use a ~22.5% corner radius.
    final radius = size * 0.225;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? _Monogram(name: name, brand: brand, size: size, inverted: inverted)
            : Image.network(
                url,
                fit: BoxFit.cover,
                // Decode at the rendered size, not the file's. A merchant
                // logo arrives at hundreds of px; decoding the original on
                // the UI thread during navigation is visible jank.
                cacheWidth: (size *
                        (MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0))
                    .round(),
                errorBuilder: (_, _, _) =>
                    _Monogram(name: name, brand: brand, size: size, inverted: inverted),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : _Monogram(name: name, brand: brand, size: size, inverted: inverted),
              ),
      ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({
    required this.name,
    required this.brand,
    required this.size,
    required this.inverted,
  });

  final String name;
  final Color brand;
  final double size;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '؟'
        : String.fromCharCodes(trimmed.runes.take(1));

    return Container(
      color: inverted ? Colors.white : brand,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: inverted ? brand : Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
