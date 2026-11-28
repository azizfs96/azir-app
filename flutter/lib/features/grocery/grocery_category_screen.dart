import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../menu/cart_controller.dart';
import '../stores/data/store_repository.dart';
import '../stores/domain/menu.dart';
import 'grocery_nav_bar.dart';
import 'grocery_product_card.dart';
import 'grocery_theme.dart';
import 'grocery_widgets.dart';

/// /s/:token/category/:id — Figma "Supermarket – Category": back and search
/// circles around a centred title, a sort pill with the product count, a row
/// of chips to switch category ("all" first), a 3-column grid of compact
/// cards fifteen at a time with a "show more" pill, and the cart bar.
class GroceryCategoryScreen extends ConsumerStatefulWidget {
  const GroceryCategoryScreen({super.key, required this.token, this.categoryId, this.featured = false});

  final String token;
  final int? categoryId;
  final bool featured;

  @override
  ConsumerState<GroceryCategoryScreen> createState() => _GroceryCategoryScreenState();
}

enum _Sort { bestSelling, priceLow, priceHigh, discount }

class _GroceryCategoryScreenState extends ConsumerState<GroceryCategoryScreen> {
  static const _pageSize = 15;

  /// null = all products; -1 = today's offers; otherwise a category id.
  late int? _selected = widget.featured ? -1 : widget.categoryId;
  _Sort _sort = _Sort.bestSelling;
  int _shown = _pageSize;

  void _select(int? id) => setState(() {
        _selected = id;
        _shown = _pageSize;
      });

  List<MenuItem> _sorted(List<MenuItem> items) {
    final list = [...items];
    switch (_sort) {
      case _Sort.bestSelling:
        list.sort((a, b) {
          if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
          if (a.isOrderable != b.isOrderable) return a.isOrderable ? -1 : 1;
          return 0;
        });
      case _Sort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _Sort.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _Sort.discount:
        list.sort((a, b) => (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0));
    }
    return list;
  }

  String _sortLabel(Strings s, _Sort sort) => switch (sort) {
        _Sort.bestSelling => s.grocerySortBestSelling,
        _Sort.priceLow => s.grocerySortPriceLow,
        _Sort.priceHigh => s.grocerySortPriceHigh,
        _Sort.discount => s.grocerySortDiscount,
      };

  Future<void> _pickSort(Strings s) async {
    AppHaptics.tick();
    final picked = await showModalBottomSheet<_Sort>(
      context: context,
      backgroundColor: Gr.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.grocerySortBy, style: Gr.text(18, weight: 800)),
              const SizedBox(height: 8),
              for (final opt in _Sort.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_sortLabel(s, opt), style: Gr.text(14, weight: opt == _sort ? 700 : 500)),
                  trailing: opt == _sort ? const Icon(Icons.check_rounded, color: Gr.primary) : null,
                  onTap: () => Navigator.of(context).pop(opt),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final store = ref.watch(storefrontProvider(widget.token)).value;
    final menu = store?.menu ?? const Menu(categories: [], uncategorised: []);
    final categories = menu.categories.where((c) => c.items.isNotEmpty).toList();
    final featured = menu.featured.where((i) => i.isAvailable).toList();
    final glyphOf = glyphByItem(menu);
    final cart = ref.watch(cartForStoreProvider(widget.token));

    final MenuCategory? current = _selected == null || _selected == -1
        ? null
        : categories.where((c) => c.id == _selected).firstOrNull;
    final title = _selected == -1
        ? s.groceryTodayOffers
        : (current?.name ?? s.groceryAllProducts);
    final all = _selected == -1
        ? featured
        : current?.items ?? menu.allItems;
    final items = _sorted(all);
    final visible = items.take(_shown).toList();
    final remaining = items.length - visible.length;

    final width = MediaQuery.sizeOf(context).width;
    final cellW = (width - Gr.pageX * 2 - 10 * 2) / 3;
    final cellH = GroceryProductCard.heightFor(cellW, GroceryCardStyle.compact);

    return Scaffold(
      backgroundColor: Gr.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(Gr.pageX, MediaQuery.paddingOf(context).top + 4, Gr.pageX, 0),
                sliver: SliverList.list(children: [
                  // Top bar: back (start), centred title, search (end).
                  Row(
                    children: [
                      GrCircleButton(
                        icon: 'back',
                        flipForRtl: true,
                        onTap: () => context.canPop() ? context.pop() : context.go('/s/${widget.token}'),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Gr.text(20, weight: 800, height: 1.25),
                        ),
                      ),
                      GrCircleButton(icon: 'search', onTap: () => context.push('/s/${widget.token}/search')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Sort row.
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _pickSort(s),
                        child: Container(
                          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 12, 8),
                          decoration: BoxDecoration(
                            color: Gr.surface,
                            borderRadius: BorderRadius.circular(Gr.pill),
                            boxShadow: Gr.pillShadow,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const GrIcon('sliders_small', size: 16),
                              const SizedBox(width: 6),
                              Text(_sortLabel(s, _sort), style: Gr.text(13, weight: 600, height: 1.25)),
                              const SizedBox(width: 6),
                              const GrIcon('sort', size: 14),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(s.groceryProductsCount(items.length), style: Gr.text(13, color: Gr.ink3)),
                    ],
                  ),
                ]),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              // Category chips: "all" first, then every category.
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                    children: [
                      GrChip(label: s.groceryAllChip, selected: _selected == null, onTap: () => _select(null)),
                      if (featured.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        GrChip(label: s.groceryTodayOffers, selected: _selected == -1, onTap: () => _select(-1)),
                      ],
                      for (final c in categories) ...[
                        const SizedBox(width: 8),
                        GrChip(label: c.name, selected: _selected == c.id, onTap: () => _select(c.id)),
                      ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 20,
                    mainAxisExtent: cellH,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => GroceryProductCard(
                      token: widget.token,
                      item: visible[i],
                      s: s,
                      style: GroceryCardStyle.compact,
                      fallbackGlyph: glyphOf[visible[i].id] ?? '🛒',
                    ),
                    childCount: visible.length,
                  ),
                ),
              ),
              if (items.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(child: Text(s.noResults, style: Gr.text(14, color: Gr.ink3))),
                  ),
                ),
              if (remaining > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Center(
                      child: GestureDetector(
                        onTap: () {
                          AppHaptics.tick();
                          setState(() => _shown += _pageSize);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                          decoration: BoxDecoration(
                            color: Gr.surface,
                            borderRadius: BorderRadius.circular(Gr.pill),
                            border: Border.all(color: Gr.primary.withValues(alpha: 0.15)),
                          ),
                          child: Text(s.groceryLoadMore(remaining), style: Gr.text(13, weight: 600, color: Gr.primary, height: 1.25)),
                        ),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(height: groceryBottomClearance(context, hasCart: !cart.isEmpty, withTabBar: false)),
              ),
            ],
          ),
          if (!cart.isEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: GroceryNavBar.bottomInset(context)),
                child: GroceryCartBar(token: widget.token),
              ),
            ),
        ],
      ),
    );
  }
}
