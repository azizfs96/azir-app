import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/location/device_location.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/open_badge.dart';
import '../stores/domain/storefront.dart';
import '../stores/presentation/store_avatar.dart';
import 'fulfillment.dart';

/// ============================================================================
/// THE STOREFRONT TOP — the design system's home header.
///
///   ┌──────────────────────────────────────┐
///   │ ◉ ◉        صباح الخير 👋              │  ← cover: brand colour, the
///   │            اسم المتجر ✓ ● مفتوح       │     logo centred, fading into
///   │               [ LOGO ]               │     the canvas; greeting +
///   │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │     identity + glass actions
///   └──────────────────────────────────────┘
///   [ 🛍 استلام ] [ 🏬 داخل المحل ] [ 🛵 توصيل ]   ← mode bar (equal pills)
///   🏬 فرع الاستلام / اسم الفرع            ⌄     ← branch row
///   ┌──────────────────────────────────────┐
///   │            promo banner              │   ← rounded 24, 1200×593
///   └──────────────────────────────────────┘
/// ============================================================================

/// Smooth-step alpha ramp for the cover → canvas fade (16 stops). Both ends
/// have zero slope, so neither the start of the fade nor the point where the
/// photo is fully gone reads as an edge — the TikTok profile look.
const _fadeStops = [
  0.0,
  0.067,
  0.133,
  0.2,
  0.267,
  0.333,
  0.4,
  0.467,
  0.533,
  0.6,
  0.667,
  0.733,
  0.8,
  0.867,
  0.933,
  1.0,
];
const _fadeRamp = [
  0.0,
  0.013,
  0.048,
  0.104,
  0.176,
  0.259,
  0.352,
  0.451,
  0.549,
  0.648,
  0.741,
  0.824,
  0.896,
  0.952,
  0.987,
  1.0,
];

/// Cover height as a fraction of the width (tall, like a profile header), and
/// how far the content below climbs into the faded zone.
const kCoverAspect = 1.45;
const kCoverOverlap = 64.0;

/// The cover (`.cover` + `.cover-top`).
class StoreCover extends StatelessWidget {
  const StoreCover({
    super.key,
    required this.store,
    required this.s,
    required this.brand,
    required this.onSearch,
    required this.onNotifications,
    required this.onShare,
    this.onBack,
  });

  final Storefront store;
  final Strings s;
  final Color brand;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final VoidCallback onShare;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final logo = logoUrlOf(store.logo);
    final greeting = DateTime.now().hour < 12
        ? s.greeting(null)
        : s.eveningGreeting;
    const shadow = [
      Shadow(color: Color(0x42000000), blurRadius: 8, offset: Offset(0, 1)),
    ];

    final monogram = StoreAvatar(
      logoPath: null,
      name: store.name,
      brandColor: store.brandColor,
      size: 120,
      inverted: true,
    );

    final cover = logoUrlOf(store.cover);

    return Stack(
      fit: StackFit.expand,
      children: [
        // The merchant's cover photo as the backdrop (brand colour until it
        // loads, or when the store has none).
        ColoredBox(color: brand),
        if (cover != null)
          AppImage(
            url: cover,
            fit: BoxFit.cover,
            placeholderColor: Colors.transparent,
            error: const SizedBox.shrink(),
          ),

        // Without a cover photo, the logo is the artwork.
        if (cover == null)
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.56,
              heightFactor: 0.46,
              child: logo != null
                  ? AppImage(
                      url: logo,
                      fit: BoxFit.contain,
                      placeholderColor: Colors.transparent,
                      error: Center(child: monogram),
                    )
                  : Center(child: monogram),
            ),
          ),

        // A soft scrim behind the status bar / actions so the white text
        // stays legible on any photo.
        Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: 0.42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
            ),
          ),
        ),

        // The photo dissolves into the page canvas (the TikTok-profile
        // fade): an eased, many-stop ramp over the lower half so there is
        // no visible band where the image ends and the background begins.
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: 0.62,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    for (final a in _fadeRamp) Ds.bg.withValues(alpha: a),
                  ],
                  stops: _fadeStops,
                ),
              ),
            ),
          ),
        ),

        // Greeting + identity on the start, glass actions on the end.
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (onBack != null) ...[
                  _Glass(icon: Icons.arrow_back_rounded, onTap: onBack!),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$greeting 👋',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.white.withValues(alpha: 0.74),
                          shadows: shadow,
                        ),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              store.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                color: Colors.white,
                                shadows: shadow,
                              ),
                            ),
                          ),
                          if (store.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 17,
                              color: Colors.white,
                            ),
                          ],
                          if (store.isOpen != null) ...[
                            const SizedBox(width: 8),
                            OpenBadge(open: store.isOpen!, s: s, compact: true),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Glass(icon: Icons.search_rounded, onTap: onSearch),
                const SizedBox(width: 10),
                _Glass(
                  icon: Icons.notifications_none_rounded,
                  onTap: onNotifications,
                ),
                if (store.deepLink != null) ...[
                  const SizedBox(width: 10),
                  _Glass(icon: Icons.ios_share_rounded, onTap: onShare),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The compact header that docks with the category chips once the cover has
/// scrolled away: the same back / name / actions row as the cover top, but on
/// the page canvas (ink on `Ds.soft` buttons instead of frosted glass).
class StoreTopBar extends StatelessWidget {
  const StoreTopBar({
    super.key,
    required this.store,
    required this.s,
    required this.onSearch,
    required this.onNotifications,
    required this.onShare,
    this.onBack,
  });

  static const double height = 56;

  final Storefront store;
  final Strings s;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final VoidCallback onShare;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            if (onBack != null) ...[
              _Round(icon: Icons.arrow_back_rounded, onTap: onBack!),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(store.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600, color: Ds.ink)),
                  ),
                  if (store.isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified_rounded, size: 16, color: Ds.ink),
                  ],
                  if (store.isOpen != null) ...[
                    const SizedBox(width: 8),
                    OpenBadge(open: store.isOpen!, s: s, compact: true),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Round(icon: Icons.search_rounded, onTap: onSearch),
            const SizedBox(width: 8),
            _Round(icon: Icons.notifications_none_rounded, onTap: onNotifications),
            if (store.deepLink != null) ...[
              const SizedBox(width: 8),
              _Round(icon: Icons.ios_share_rounded, onTap: onShare),
            ],
          ],
        ),
      ),
    );
  }
}

/// A 40pt round button on the canvas (the docked header's counterpart of `_Glass`).
class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Ds.soft,
      shape: const CircleBorder(side: BorderSide(color: Ds.line)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 20, color: Ds.ink)),
      ),
    );
  }
}

/// A 44pt frosted-glass round button (`.cover-top .round`).
class _Glass extends StatelessWidget {
  const _Glass({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.white.withValues(alpha: 0.15),
          shape: CircleBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.26)),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: const SizedBox(width: 44, height: 44),
          ),
        ),
      ),
    )._withIcon(icon);
  }
}

extension on Widget {
  Widget _withIcon(IconData icon) => Stack(
    alignment: Alignment.center,
    children: [
      this,
      IgnorePointer(child: Icon(icon, size: 21, color: Colors.white)),
    ],
  );
}

/// The scrolling block under the cover: mode bar, branch row, promo banner.
class RestaurantHeader extends ConsumerWidget {
  const RestaurantHeader({
    super.key,
    required this.store,
    required this.s,
    required this.brand,
  });

  final Storefront store;
  final Strings s;
  final Color brand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = enabledModes(store.configuration);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(fulfillmentModeProvider.notifier)
          .ensureDefault(store.token, modes);
    });
    final selected =
        ref.watch(modeForStoreProvider(store.token)) ??
        (modes.isNotEmpty ? modes.first : null);
    final cover = logoUrlOf(store.cover);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (modes.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _ModeBar(
              modes: modes,
              selected: selected,
              brand: brand,
              s: s,
              onTap: (m) {
                AppHaptics.tick();
                ref.read(fulfillmentModeProvider.notifier).set(store.token, m);
              },
            ),
          ),
        if (store.branches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: _BranchRow(store: store, s: s, brand: brand),
          ),
        if (cover != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _PromoBanner(url: cover),
          ),
      ],
    );
  }
}

/// Equal-width fulfilment pills (`.modebar`, 3-up or 2-up).
class _ModeBar extends StatelessWidget {
  const _ModeBar({
    required this.modes,
    required this.selected,
    required this.brand,
    required this.s,
    required this.onTap,
  });

  final List<FulfillmentMode> modes;
  final FulfillmentMode? selected;
  final Color brand;
  final Strings s;
  final void Function(FulfillmentMode) onTap;

  @override
  Widget build(BuildContext context) {
    final cols = modes.length == 3 ? 3 : 2;
    final rows = <Widget>[];
    for (var i = 0; i < modes.length; i += cols) {
      final chunk = modes.sublist(i, (i + cols).clamp(0, modes.length));
      rows.add(
        Row(
          children: [
            for (var j = 0; j < cols; j++) ...[
              if (j > 0) const SizedBox(width: 10),
              Expanded(
                child: j < chunk.length
                    ? _ModePill(
                        mode: chunk[j],
                        selected: chunk[j] == selected,
                        brand: brand,
                        compact: cols == 3,
                        s: s,
                        onTap: () => onTap(chunk[j]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          rows[i],
        ],
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.mode,
    required this.selected,
    required this.brand,
    required this.compact,
    required this.s,
    required this.onTap,
  });

  final FulfillmentMode mode;
  final bool selected;
  final Color brand;
  final bool compact;
  final Strings s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? brand : Ds.ink2;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.dur(context, AppMotion.base),
        curve: AppMotion.curve,
        height: 52,
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 8),
        decoration: BoxDecoration(
          color: selected ? Ds.mix(brand, Ds.surface, 0.10) : Ds.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? brand : Ds.line, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(mode.icon, size: compact ? 19 : 21, color: fg),
            SizedBox(width: compact ? 6 : 8),
            Flexible(
              child: Text(
                mode.label(s),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 14 : 15.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The branch line (`.loc`): brand icon, caption + name, a soft chevron — and
/// how far the nearest branch is, once the customer's location is known.
class _BranchRow extends ConsumerWidget {
  const _BranchRow({required this.store, required this.s, required this.brand});
  final Storefront store;
  final Strings s;
  final Color brand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final here = ref.watch(deviceLocationProvider).value;
    // Show the nearest branch when we can tell; otherwise the first one.
    var branch = store.branches.first;
    double? km;
    for (final b in store.branches) {
      final d = here?.kmTo(b.latitude, b.longitude);
      if (d != null && (km == null || d < km)) {
        km = d;
        branch = b;
      }
    }
    return Row(
      children: [
        Icon(Icons.storefront_rounded, size: 24, color: brand),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.pickupBranch,
                style: const TextStyle(fontSize: 12.5, color: Ds.ink3),
              ),
              Text(
                branch.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Ds.ink,
                ),
              ),
            ],
          ),
        ),
        if (km != null) ...[
          Text(
            formatDistance(s, km),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Ds.ink2),
          ),
          const SizedBox(width: 4),
        ],
        const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Ds.ink3),
      ],
    );
  }
}

/// The promotional banner (`.banner`): rounded 24, 1200×593, the merchant's image.
class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 1200 / 593,
        child: AppImage(
          url: url,
          fit: BoxFit.cover,
          placeholderColor: Ds.bannerFill,
          error: const ColoredBox(color: Ds.bannerFill),
        ),
      ),
    );
  }
}
