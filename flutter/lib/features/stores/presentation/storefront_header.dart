import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/strings.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/map_targets.dart';
import '../domain/storefront.dart';
import 'store_avatar.dart';

/// ============================================================================
/// THE STOREFRONT HEADER
///
///   ┌──────────────────────────────┐
///   │  ‹            cover      ↗   │
///   │                              │
///   │  ┌────┐                      │   logo straddles the seam
///   ╰──┤LOGO├──────────────────────╯
///      └────┘
///      جلو بيوتي ✓
///      الرياض · شارع العليا
///      [نساء فقط] [● مفتوح الآن]
///      وصف المتجر…
///      🕐 الأحد-السبت    📍 الموقع
///
/// LAYOUT NOTE — this is why the pieces used to overlap:
///
/// The obvious way to make the sheet ride up over the cover is
/// `Transform.translate`, but a Transform moves only the PAINT, never the
/// layout. Stacking three of them made every element paint 28px higher than
/// the space it still occupied, so the reserved gaps and the visible content
/// drifted apart and collided.
///
/// Instead: ONE Stack. The sheet is placed with real top padding so its layout
/// genuinely starts inside the cover, and the logo is `Positioned` so it
/// straddles the seam without affecting anyone's size. Layout and paint agree,
/// so nothing can overlap.
/// ============================================================================
/// Physical pixels the cover actually needs — capped so a 4000px upload
/// from before server-side shrinking never costs a 4000px decode.
int _coverDecodeWidth(BuildContext context) {
  final logical = MediaQuery.maybeSizeOf(context)?.width ?? 430;
  final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;

  return (logical * ratio).clamp(320, 1600).round();
}

class StorefrontHeader extends StatelessWidget {
  const StorefrontHeader({
    super.key,
    required this.store,
    required this.s,
    required this.brand,
    required this.onShare,
    this.onOpenMap,
  });

  final Storefront store;
  final Strings s;
  final Color brand;
  final VoidCallback onShare;
  final VoidCallback? onOpenMap;

  static const _coverHeight = 200.0;

  /// How far the white sheet rides up over the cover photo.
  static const _sheetOverlap = 24.0;

  static const _logoSize = 72.0;
  static const _logoPadding = 6.0;
  static const _logoBox = _logoSize + _logoPadding * 2;

  /// How much of the logo card hangs below the seam, into the sheet.
  static const _logoDrop = _logoBox * 0.5;

  @override
  Widget build(BuildContext context) {
    final sheetTop = _coverHeight - _sheetOverlap;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. Cover photo, pinned to the top.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _coverHeight,
          child: _Cover(store: store, brand: brand, onShare: onShare),
        ),

        // 2. The white sheet. Its top padding is REAL layout, so the Stack
        //    sizes itself correctly around it and nothing below can collide.
        Padding(
          padding: EdgeInsets.only(top: sheetTop),
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            // Enough room for the part of the logo hanging into the sheet.
            padding: EdgeInsets.fromLTRB(20, _logoDrop + 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Identity(store: store, s: s, brand: brand),
                const SizedBox(height: 14),
                _Chips(store: store, s: s),
                if (store.description != null && store.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    store.description!,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.6,
                      color: AppColors.ink500,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _InfoTiles(store: store, s: s, brand: brand, onOpenMap: onOpenMap),
              ],
            ),
          ),
        ),

        // 3. The logo card, straddling the seam. Positioned, so it contributes
        //    nothing to layout — the sheet's top padding already reserved it.
        PositionedDirectional(
          start: 20,
          top: sheetTop - (_logoBox - _logoDrop),
          child: Container(
            padding: const EdgeInsets.all(_logoPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: StoreAvatar(
              name: store.name,
              logoPath: store.logo,
              brandColor: store.brandColor,
              size: _logoSize,
            ),
          ),
        ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.store, required this.brand, required this.onShare});

  final Storefront store;
  final Color brand;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final coverUrl = logoUrlOf(store.cover);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Without a photo the merchant's brand colour stands in — a grey
        // placeholder would make every store look broken.
        if (coverUrl == null)
          ColoredBox(color: brand)
        else
          Image.network(
            coverUrl,
            fit: BoxFit.cover,
            // The freeze on opening a storefront traced to decoding the
            // full-resolution cover during the push animation. Decode at
            // (at most) the screen's physical width instead.
            cacheWidth: _coverDecodeWidth(context),
            errorBuilder: (_, _, _) => ColoredBox(color: brand),
          ),

        // Scrim so the controls stay legible over any photo.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 120,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.38), Colors.transparent],
              ),
            ),
          ),
        ),

        Positioned(
          top: MediaQuery.paddingOf(context).top + 6,
          left: 12,
          right: 12,
          child: Row(
            children: [
              _CircleButton(
                icon: Icons.arrow_back_rounded,
                /*
                 * Back to wherever we came from — or the app home when there
                 * is nowhere to pop to.
                 *
                 * The storefront is usually PUSHED from home, so a pop works.
                 * But returning here from the confirmation screen uses go(),
                 * which replaces the whole stack and leaves the storefront as
                 * the root: maybePop() then does nothing, and this button
                 * looked broken. Fall back to go('/') so it always leads home.
                 */
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.go('/');
                  }
                },
              ),
              const Spacer(),
              _CircleButton(icon: Icons.ios_share_rounded, onTap: onShare),
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 20, color: AppColors.ink900),
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.store, required this.s, required this.brand});

  final Storefront store;
  final Strings s;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    // "Riyadh · Olaya Street" without a dangling separator when a half is
    // missing — most merchants fill in one field, not both.
    final place = [store.location?.city, store.location?.address]
        .where((v) => v != null && v.trim().isNotEmpty)
        .join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                store.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink900,
                  height: 1.25,
                ),
              ),
            ),
            if (store.isVerified) ...[
              const SizedBox(width: 6),
              Icon(Icons.verified_rounded, size: 20, color: brand),
            ],
          ],
        ),
        if (place.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            place,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.ink500),
          ),
        ],
      ],
    );
  }
}

/// Facts about the venue, not marketing claims — each chip is real data.
class _Chips extends StatelessWidget {
  const _Chips({required this.store, required this.s});

  final Storefront store;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    final hours = store.openingHours;

    final chips = <(IconData, String, bool)>[
      if (store.genderPolicy == 'women_only') (Icons.female_rounded, s.womenOnly, false),
      if (store.genderPolicy == 'men_only') (Icons.male_rounded, s.menOnly, false),
      if (hours != null)
        hours.isOpenNow
            ? (Icons.circle, s.openNow, true)
            : (Icons.circle_outlined, s.closedNow, false),
      if (store.branches.length > 1)
        (Icons.storefront_outlined, s.multipleBranches, false),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (icon, label, isOpen) in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: isOpen ? AppColors.okSoft : AppColors.ink100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: isOpen ? 8 : 14,
                  color: isOpen ? AppColors.ok : AppColors.ink500,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: isOpen ? AppColors.ok : AppColors.ink700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Hours and location — the two questions asked before booking.
class _InfoTiles extends StatelessWidget {
  const _InfoTiles({
    required this.store,
    required this.s,
    required this.brand,
    required this.onOpenMap,
  });

  final Storefront store;
  final Strings s;
  final Color brand;
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final hours = store.openingHours;
    final location = store.location;
    final hasMapTargets = onOpenMap != null && mapTargets(store).isNotEmpty;

    final tiles = <Widget>[
      if (hours != null)
        _Tile(icon: Icons.schedule_rounded, brand: brand, label: hours.days, value: hours.hours),
      if (hasMapTargets || (location != null && location.hasAny))
        _Tile(
          icon: Icons.place_outlined,
          brand: brand,
          label: s.location,
          // Tappable whenever ANY destination exists — branches count too,
          // not just a pasted store-profile link. The old condition left the
          // tile inert for every merchant who set locations on branches.
          value: hasMapTargets ? s.viewOnMap : (location?.city ?? ''),
          onTap: hasMapTargets ? onOpenMap : null,
        ),
    ];

    if (tiles.isEmpty) return const SizedBox.shrink();

    /*
     * Side by side only when there is genuinely room.
     *
     * Arabic opening hours ("10:00 ص - 10:00 م") are noticeably longer than
     * the English equivalent, and forcing two columns on a 375pt phone broke
     * the line after "10:00" and left a lone "م" on the next row. Below the
     * threshold the tiles stack instead — full width, always readable.
     */
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsSideBySide = constraints.maxWidth >= 380 && tiles.length > 1;

        if (!fitsSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i != tiles.length - 1) const SizedBox(height: 14),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              Expanded(child: tiles[i]),
              if (i != tiles.length - 1) const SizedBox(width: 14),
            ],
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.brand,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final Color brand;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink900,
                  ),
                ),
                const SizedBox(height: 3),
                // One line, shrinking rather than wrapping: a time range broken
                // across two lines reads as corrupted text, not as a time.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      color: onTap != null ? brand : AppColors.ink500,
                      fontWeight: onTap != null ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
