import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../stores/data/store_repository.dart';
import '../stores/domain/menu.dart';
import '../stores/presentation/store_avatar.dart';
import 'category_glyph.dart';
import 'grocery_nav_bar.dart';
import 'grocery_product_card.dart';
import 'grocery_theme.dart';

/// /s/:token/categories — the "Categories" tab: a side rail of categories and
/// the selected one's products as a grid. Opens on a given category or on the
/// best sellers when asked (`?category=` / `?featured=1`).
class GroceryCategoriesScreen extends ConsumerStatefulWidget {
  const GroceryCategoriesScreen({super.key, required this.token, this.initialCategory, this.featured = false});

  final String token;
  final int? initialCategory;
  final bool featured;

  @override
  ConsumerState<GroceryCategoriesScreen> createState() => _GroceryCategoriesScreenState();
}

class _GroceryCategoriesScreenState extends ConsumerState<GroceryCategoriesScreen> {
  /// null = best sellers, otherwise a category id.
  int? _selected;
  bool _initialised = false;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final store = ref.watch(storefrontProvider(widget.token)).value;
    final menu = store?.menu ?? const Menu(categories: [], uncategorised: []);
    final categories = menu.categories.where((c) => c.items.isNotEmpty).toList();
    final featured = menu.featured.toList();

    if (!_initialised && store != null) {
      _initialised = true;
      _selected = widget.featured
          ? null
          : (widget.initialCategory ?? (featured.isNotEmpty ? null : categories.firstOrNull?.id));
    }

    final items = _selected == null
        ? featured
        : (categories.where((c) => c.id == _selected).firstOrNull?.items ?? const <MenuItem>[]);
    final title = _selected == null
        ? s.groceryBestSellers
        : (categories.where((c) => c.id == _selected).firstOrNull?.name ?? '');
    final glyphOf = <int, String>{
      for (final c in menu.categories)
        for (final i in c.items) i.id: categoryGlyph(c.name),
    };

    // Two equal columns in the space right of the rail: screen − rail − the
    // 20pt page margin − one 12pt gutter. Rows are as tall as the card needs.
    final gridW = MediaQuery.sizeOf(context).width - _railWidth - Gr.pageX;
    final cellW = (gridW - Gr.s12) / 2;
    final cellH = GroceryProductCard.heightFor(cellW);
    final bottomClearance = Gr.s32 + GroceryNavBar.height + MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Gr.bg,
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(Gr.pageX, MediaQuery.paddingOf(context).top + Gr.s8, Gr.pageX, Gr.s16),
                child: Row(
                  children: [
                    Material(
                      color: Gr.surface2,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.of(context).maybePop(),
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Transform.flip(
                            flipX: Directionality.of(context) == TextDirection.rtl,
                            child: const Icon(Icons.arrow_back_rounded, size: 20, color: Gr.ink),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: Gr.s12),
                    Expanded(
                      child: Text(s.groceryCategories,
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Gr.ink)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Side rail: the 20pt page margin outside, 12 to the grid.
                    SizedBox(
                      width: _railWidth,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(Gr.pageX, 0, Gr.s12, bottomClearance),
                        children: [
                          if (featured.isNotEmpty)
                            _RailItem(
                              label: s.groceryBestSellers,
                              icon: Icons.local_fire_department_rounded,
                              selected: _selected == null,
                              onTap: () => setState(() => _selected = null),
                            ),
                          for (final c in categories)
                            _RailItem(
                              label: c.name,
                              image: c.image,
                              glyph: categoryGlyph(c.name),
                              selected: _selected == c.id,
                              onTap: () => setState(() => _selected = c.id),
                            ),
                        ],
                      ),
                    ),
                    // Products of the selected category.
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 0, Gr.pageX, Gr.s16),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(title,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Gr.ink)),
                                  ),
                                  Text('${items.length}', style: const TextStyle(fontSize: 12.5, color: Gr.ink3)),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(0, 0, Gr.pageX, bottomClearance),
                            sliver: SliverGrid(
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: Gr.s16,
                                crossAxisSpacing: Gr.s12,
                                mainAxisExtent: cellH,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (_, i) => GroceryProductCard(
                                  token: widget.token,
                                  item: items[i],
                                  s: s,
                                  fallbackGlyph: glyphOf[items[i].id] ?? '🛒',
                                ),
                                childCount: items.length,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: GroceryNavBar(token: widget.token, active: GroceryTab.categories),
          ),
        ],
      ),
    );
  }
}

/// Rail column: 20 margin + 72 item + 12 gutter to the grid.
const _railWidth = Gr.pageX + 72 + Gr.s12;

class _RailItem extends StatelessWidget {
  const _RailItem({required this.label, required this.selected, required this.onTap, this.image, this.icon, this.glyph});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? image;
  final IconData? icon;

  /// Emoji fallback when there is no image (null → the icon).
  final String? glyph;

  Widget _fallback() => glyph != null
      ? Center(child: Text(glyph!, style: const TextStyle(fontSize: 22, height: 1)))
      : Icon(icon ?? Icons.eco_rounded, color: Gr.accent, size: 20);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        AppHaptics.tick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: AppMotion.dur(context, AppMotion.fast),
        margin: const EdgeInsets.only(bottom: Gr.s8),
        padding: const EdgeInsets.symmetric(vertical: Gr.s8, horizontal: Gr.s4),
        decoration: BoxDecoration(
          color: selected ? Gr.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(Gr.s16),
          border: Border.all(color: selected ? Gr.accent : Colors.transparent, width: 1.5),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: Gr.surface, shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: image != null
                  ? AppImage(url: logoUrlOf(image), placeholderColor: Gr.surface, error: _fallback())
                  : _fallback(),
            ),
            const SizedBox(height: Gr.s8),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Gr.ink : Gr.ink2,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
