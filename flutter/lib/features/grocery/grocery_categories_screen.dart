import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../menu/cart_controller.dart';
import '../stores/data/store_repository.dart';
import '../stores/domain/menu.dart';
import 'grocery_category_screen.dart';
import 'grocery_nav_bar.dart';
import 'grocery_theme.dart';
import 'grocery_widgets.dart';

/// /s/:token/categories — Figma "Supermarket – Categories": a 26pt title with
/// the store's counts under it, the dark cart button, and a 3-column grid of
/// photo cards (112pt, 20pt corners) with the name and product count.
///
/// `?category=` / `?featured=1` open the category's product page directly
/// (older links and the home page's "see all").
class GroceryCategoriesScreen extends ConsumerWidget {
  const GroceryCategoriesScreen({super.key, required this.token, this.initialCategory, this.featured = false});

  final String token;
  final int? initialCategory;
  final bool featured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialCategory != null || featured) {
      return GroceryCategoryScreen(token: token, categoryId: initialCategory, featured: featured);
    }

    final s = Strings.of(context);
    final store = ref.watch(storefrontProvider(token)).value;
    final menu = store?.menu ?? const Menu(categories: [], uncategorised: []);
    final categories = menu.categories.where((c) => c.items.isNotEmpty).toList();
    final cart = ref.watch(cartForStoreProvider(token));
    final products = categories.fold<int>(0, (n, c) => n + c.items.length) + menu.uncategorised.length;

    final width = MediaQuery.sizeOf(context).width;
    final cellW = (width - Gr.pageX * 2 - 12 * 2) / 3;
    final cellH = cellW + 8 + 13 * 1.25 * 2 + 11 * 1.25 + 4;

    return Scaffold(
      backgroundColor: Gr.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(Gr.pageX, MediaQuery.paddingOf(context).top + 4, Gr.pageX, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.groceryShopByCategory, style: Gr.text(26, weight: 800, height: 1.25)),
                            Text(
                              s.groceryCategoriesSummary(categories.length, products),
                              style: Gr.text(13, color: Gr.ink3, height: 1.25),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GrCircleButton(
                        icon: 'cart',
                        dark: true,
                        badge: cart.count,
                        onTap: () => context.push('/s/$token/cart'),
                        semanticLabel: s.cart,
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 18,
                    mainAxisExtent: cellH,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _CategoryCard(
                      category: categories[i],
                      count: s.groceryProductsCount(categories[i].items.length),
                      onTap: () {
                        AppHaptics.tick();
                        context.push('/s/$token/category/${categories[i].id}');
                      },
                    ),
                    childCount: categories.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(height: groceryBottomClearance(context, hasCart: !cart.isEmpty)),
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!cart.isEmpty) ...[GroceryCartBar(token: token), const SizedBox(height: 12)],
                GroceryNavBar(token: token, active: GroceryTab.categories),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Figma "Category Card": square white photo with 20pt corners and the card
/// shadow, the name (13 bold, up to two lines) and the count (11 grey).
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.count, required this.onTap});

  final MenuCategory category;
  final String count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Gr.surface,
                borderRadius: BorderRadius.circular(Gr.rCategoryCard),
                boxShadow: Gr.cardShadow,
              ),
              clipBehavior: Clip.antiAlias,
              child: GrCategoryPhoto(category: category, glyphSize: 48),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Gr.text(13, weight: 700, height: 1.25)),
                Text(count, maxLines: 1, style: Gr.text(11, color: Gr.ink3, height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
