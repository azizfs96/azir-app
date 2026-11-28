import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/widgets/app_image.dart';
import '../stores/domain/menu.dart';
import '../stores/presentation/store_avatar.dart';
import 'category_glyph.dart';
import 'grocery_theme.dart';

/// Shared pieces of the supermarket template, each one a component of the
/// Figma design (names in the doc comments).

/// A 44pt round button: white with the pill shadow, or dark green with an
/// optional lime count badge (Figma "Cart" / "Back" / "Search" circles).
class GrCircleButton extends StatelessWidget {
  const GrCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.dark = false,
    this.badge = 0,
    this.flipForRtl = false,
    this.semanticLabel,
  });

  final String icon;
  final VoidCallback onTap;
  final bool dark;
  final int badge;
  final bool flipForRtl;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: () {
          AppHaptics.tick();
          onTap();
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: dark ? Gr.primary : Gr.surface,
                  shape: BoxShape.circle,
                  boxShadow: dark ? null : Gr.pillShadow,
                ),
                child: Center(child: GrIcon(icon, size: 20, flipForRtl: flipForRtl)),
              ),
              if (badge > 0)
                PositionedDirectional(
                  top: -2,
                  end: -3,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Gr.lime, borderRadius: BorderRadius.circular(9)),
                    child: Text('$badge', style: Gr.text(10, weight: 800, color: Gr.onLime, height: 1)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma "Section Header": the title at the start (20 extrabold) and a grey
/// "see all" with a small arrow at the end. [leading] sits beside the title
/// (the countdown on "today's offers").
class GrSectionHeader extends StatelessWidget {
  const GrSectionHeader({super.key, required this.title, this.onSeeAll, this.leading, this.size = 20});

  final String title;
  final VoidCallback? onSeeAll;
  final Widget? leading;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Gr.text(size, weight: 800)),
              ),
              if (leading != null) ...[const SizedBox(width: 8), leading!],
            ],
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.seeAll, style: Gr.text(13, weight: 600, color: Gr.ink2)),
                const SizedBox(width: 4),
                const GrIcon('arrow_small', size: 14, flipForRtl: true),
              ],
            ),
          ),
      ],
    );
  }
}

/// Figma "Category Tile" (home): a 64pt white photo tile with 10pt corners and
/// the tile shadow, the name in 12pt bold under it.
class GrCategoryTile extends StatelessWidget {
  const GrCategoryTile({super.key, required this.category, required this.onTap, this.width = 64});

  final MenuCategory category;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppHaptics.tick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width + 8,
        child: Column(
          children: [
            Container(
              width: width,
              height: width,
              decoration: BoxDecoration(
                color: Gr.surface,
                borderRadius: BorderRadius.circular(Gr.rCategoryTile),
                boxShadow: Gr.tileShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: GrCategoryPhoto(category: category, glyphSize: 30),
            ),
            const SizedBox(height: 8),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Gr.text(12, weight: 700),
            ),
          ],
        ),
      ),
    );
  }
}

/// The category's photo filling its tile, or its emoji on white until the
/// merchant uploads one.
class GrCategoryPhoto extends StatelessWidget {
  const GrCategoryPhoto({super.key, required this.category, required this.glyphSize});

  final MenuCategory category;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    final glyph = Center(child: Text(categoryGlyph(category.name), style: TextStyle(fontSize: glyphSize, height: 1)));
    if (category.image == null) return glyph;
    return AppImage(url: logoUrlOf(category.image), fit: BoxFit.cover, placeholderColor: Gr.surface, error: glyph);
  }
}

/// Figma "Chip": a pill, dark green when selected, white with the chip shadow
/// otherwise. 16/7 padding, 13pt semibold.
class GrChip extends StatelessWidget {
  const GrChip({super.key, required this.label, required this.onTap, this.selected = false, this.leading, this.trailing});

  final String label;
  final VoidCallback onTap;
  final bool selected;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppHaptics.tick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? Gr.primary : Gr.surface,
          borderRadius: BorderRadius.circular(Gr.pill),
          boxShadow: selected ? null : Gr.chipShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 6)],
            Text(label, style: Gr.text(13, weight: 600, color: selected ? Colors.white : Gr.ink, height: 1.25)),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Figma "Search" (home): a 52pt white pill with the search glyph and hint on
/// the start side and a dark 40pt filter circle on the end side.
class GrSearchPill extends StatelessWidget {
  const GrSearchPill({super.key, required this.hint, required this.onTap, required this.onFilter});

  final String hint;
  final VoidCallback onTap;
  final VoidCallback onFilter;

  static const height = 52.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsetsDirectional.only(start: 18, end: 6),
        decoration: BoxDecoration(
          color: Gr.surface,
          borderRadius: BorderRadius.circular(Gr.pill),
          boxShadow: Gr.searchShadow,
        ),
        child: Row(
          children: [
            const GrIcon('search', size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: Gr.text(14, color: Gr.ink3)),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                AppHaptics.tick();
                onFilter();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: Gr.primary, shape: BoxShape.circle),
                child: const Center(child: GrIcon('sliders', size: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Figma "Countdown": HH : MM : SS to the end of the day in dark 6pt-rounded
/// boxes with lime digits. Ticks once a second while visible.
class GrCountdown extends StatefulWidget {
  const GrCountdown({super.key});

  @override
  State<GrCountdown> createState() => _GrCountdownState();
}

class _GrCountdownState extends State<GrCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final left = midnight.difference(now);
    String two(int n) => n.toString().padLeft(2, '0');
    final parts = [two(left.inHours), two(left.inMinutes % 60), two(left.inSeconds % 60)];

    Widget digit(String d) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: Gr.primary, borderRadius: BorderRadius.circular(6)),
          child: Text(d, style: Gr.text(12, weight: 700, color: Gr.lime, height: 1.4)),
        );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          digit(parts[0]),
          _colon(),
          digit(parts[1]),
          _colon(),
          digit(parts[2]),
        ],
      ),
    );
  }

  Widget _colon() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Text(':', style: Gr.text(12, weight: 700, color: Gr.primary)),
      );
}

/// "صباح الخير 👋" before noon, "مساء الخير 👋" after.
String groceryGreeting(Strings s, [DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  return h < 12 ? s.groceryGoodMorning : s.groceryGoodEvening;
}

/// Category emoji per item id, for products without a photo.
Map<int, String> glyphByItem(Menu menu) => {
      for (final c in menu.categories)
        for (final i in c.items) i.id: categoryGlyph(c.name),
    };
