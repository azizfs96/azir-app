import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/open_badge.dart';
import '../../core/widgets/riyal_price.dart';
import '../menu/cart_controller.dart';
import '../stores/data/store_repository.dart';
import '../stores/domain/menu.dart';
import '../stores/domain/storefront.dart';
import '../stores/presentation/store_avatar.dart';
import 'grocery_nav_bar.dart';
import 'grocery_product_card.dart';
import 'grocery_theme.dart';

/// ============================================================================
/// THE SUPERMARKET STOREFRONT — the grocery home from the design reference:
/// a dark-green canvas, a greeting + hero line beside the store's photo, a
/// search field, round category chips, a promo banner, the best sellers as a
/// horizontal strip with discount badges and one-tap "+", then every category
/// as a product grid, a features row, and a five-tab bottom nav.
/// ============================================================================
class GroceryStorefront extends ConsumerStatefulWidget {
  const GroceryStorefront({
    super.key,
    required this.store,
    required this.s,
    required this.token,
    required this.onShare,
  });

  final Storefront store;
  final Strings s;
  final String token;
  final VoidCallback onShare;

  @override
  ConsumerState<GroceryStorefront> createState() => _GroceryStorefrontState();
}

class _GroceryStorefrontState extends ConsumerState<GroceryStorefront> {
  final _scroll = ScrollController();
  final Map<int, GlobalKey> _sectionKeys = {};

  Storefront get store => widget.store;
  Strings get s => widget.s;
  Menu get menu => store.menu ?? const Menu(categories: [], uncategorised: []);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpTo(int categoryId) {
    AppHaptics.tick();
    final key = _sectionKeys[categoryId];
    final ctx = key?.currentContext;
    if (ctx == null) {
      context.push('/s/${widget.token}/categories?category=$categoryId');
      return;
    }
    Scrollable.ensureVisible(
      ctx,
      duration: AppMotion.dur(context, AppMotion.slow),
      curve: AppMotion.curve,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = menu.categories.where((c) => c.items.isNotEmpty).toList();
    final featured = menu.featured.where((i) => i.isAvailable).toList();
    final promo = store.popups.isNotEmpty ? store.popups.first.image : store.cover;
    final cart = ref.watch(cartForStoreProvider(widget.token));

    return ColoredBox(
      color: Gr.bg,
      child: Stack(
        children: [
          RefreshIndicator(
            color: Gr.accent,
            backgroundColor: Gr.surface,
            onRefresh: () async => ref.invalidate(storefrontProvider(widget.token)),
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverToBoxAdapter(child: _Header(store: store, s: s, token: widget.token, onShare: widget.onShare)),
                SliverToBoxAdapter(child: _SearchField(token: widget.token, s: s)),
                if (categories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _CategoryStrip(categories: categories, onTap: _jumpTo),
                  ),
                if (promo != null)
                  SliverToBoxAdapter(
                    child: _PromoBanner(
                      image: promo,
                      s: s,
                      onTap: () => categories.isEmpty ? null : _jumpTo(categories.first.id),
                    ),
                  ),
                if (featured.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: _SectionTitle(
                      title: s.groceryBestSellers,
                      action: s.seeAll,
                      onAction: () => context.push('/s/${widget.token}/categories?featured=1'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 268,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: featured.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (_, i) =>
                            GroceryProductCard(token: widget.token, item: featured[i], s: s, width: 164),
                      ),
                    ),
                  ),
                ],
                SliverToBoxAdapter(child: _FeaturesRow(s: s)),
                for (final category in categories) ...[
                  SliverToBoxAdapter(
                    child: KeyedSubtree(
                      key: _sectionKeys.putIfAbsent(category.id, GlobalKey.new),
                      child: _SectionTitle(
                        title: category.name,
                        action: s.seeAll,
                        onAction: () => context.push('/s/${widget.token}/categories?category=${category.id}'),
                      ),
                    ),
                  ),
                  _ProductGrid(token: widget.token, items: category.items, s: s),
                ],
                if (menu.uncategorised.isNotEmpty) ...[
                  SliverToBoxAdapter(child: _SectionTitle(title: s.groceryAllProducts)),
                  _ProductGrid(token: widget.token, items: menu.uncategorised, s: s),
                ],
                if (menu.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          const Icon(Icons.shopping_basket_outlined, color: Gr.ink3, size: 40),
                          const SizedBox(height: 12),
                          Text(s.menuEmpty, style: const TextStyle(color: Gr.ink2, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                // Room so the floating cart bar + nav never hide the last row.
                const SliverToBoxAdapter(child: SizedBox(height: 150)),
              ],
            ),
          ),
          // The nav bar sits on the canvas edge; the cart pill floats above it.
          Align(
            alignment: Alignment.bottomCenter,
            child: GroceryNavBar(token: widget.token, active: GroceryTab.home),
          ),
          if (!cart.isEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 76),
                  child: _CartPill(token: widget.token, s: s),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.store, required this.s, required this.token, required this.onShare});

  final Storefront store;
  final Strings s;
  final String token;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final hero = store.cover ?? store.logo;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, top + 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RoundIcon(
                icon: context.canPop() ? Icons.arrow_back_rounded : Icons.menu_rounded,
                onTap: context.canPop() ? () => context.pop() : onShare,
                flipForRtl: context.canPop(),
              ),
              const SizedBox(width: 10),
              StoreAvatar(name: store.name, logoPath: store.logo, brandColor: store.brandColor, size: 34),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  store.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Gr.ink),
                ),
              ),
              if (store.isOpen != null) ...[
                OpenBadge(open: store.isOpen!, s: s, compact: true),
                const SizedBox(width: 8),
              ],
              _RoundIcon(icon: Icons.notifications_none_rounded, onTap: () => context.push('/notifications')),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.groceryWelcome, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Gr.accent)),
                    const SizedBox(height: 6),
                    Text(
                      s.groceryHeroTitle,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Gr.ink, height: 1.15),
                    ),
                    Text(
                      s.groceryHeroAccent,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Gr.accent, height: 1.15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (store.description ?? '').trim().isNotEmpty ? store.description! : s.groceryHeroHint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: Gr.ink2, height: 1.45),
                    ),
                  ],
                ),
              ),
              if (hero != null) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    width: 128,
                    height: 128,
                    child: AppImage(
                      url: logoUrlOf(hero),
                      placeholderColor: Gr.surface2,
                      error: const ColoredBox(color: Gr.surface2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.flipForRtl = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool flipForRtl;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Material(
      color: Gr.surface2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Transform.flip(flipX: flipForRtl && rtl, child: Icon(icon, size: 20, color: Gr.ink)),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.token, required this.s});

  final String token;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Gr.surface2,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/s/$token/search'),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: Gr.ink3, size: 20),
                      const SizedBox(width: 8),
                      Text(s.grocerySearchHint, style: const TextStyle(color: Gr.ink3, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Material(
            color: Gr.accent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.push('/s/$token/categories'),
              child: const SizedBox(width: 48, height: 48, child: Icon(Icons.tune_rounded, color: Gr.onAccent, size: 20)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({required this.categories, required this.onTap});

  final List<MenuCategory> categories;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) {
          final c = categories[i];
          return GestureDetector(
            onTap: () => onTap(c.id),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 72,
              child: Column(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: Gr.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: i == 0 ? Gr.accent : Gr.line, width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: c.image != null
                        ? AppImage(url: logoUrlOf(c.image), placeholderColor: Gr.surface2, error: const _CategoryGlyph())
                        : const _CategoryGlyph(),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    c.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Gr.ink2, height: 1.2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryGlyph extends StatelessWidget {
  const _CategoryGlyph();

  @override
  Widget build(BuildContext context) => const Icon(Icons.eco_rounded, color: Gr.accent, size: 26);
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.image, required this.s, required this.onTap});

  final String image;
  final Strings s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: AspectRatio(
          aspectRatio: 2.3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppImage(url: logoUrlOf(image), placeholderColor: Gr.surface2, error: const ColoredBox(color: Gr.surface2)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [Color(0xE60C1A12), Color(0x330C1A12)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(s.groceryPromoKicker.toUpperCase(),
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Gr.accent, letterSpacing: 0.6)),
                    const SizedBox(height: 4),
                    Text(s.groceryHeroHint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Gr.ink, height: 1.25)),
                    const SizedBox(height: 10),
                    Material(
                      color: Gr.accent,
                      borderRadius: BorderRadius.circular(99),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(s.shopNow, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Gr.onAccent)),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward_rounded, size: 14, color: Gr.onAccent),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Gr.ink))),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Gr.accent)),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward_rounded, size: 14, color: Gr.accent),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.token, required this.items, required this.s});

  final String token;
  final List<MenuItem> items;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 262,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => GroceryProductCard(token: token, item: items[i], s: s),
          childCount: items.length,
        ),
      ),
    );
  }
}

class _FeaturesRow extends StatelessWidget {
  const _FeaturesRow({required this.s});

  final Strings s;

  @override
  Widget build(BuildContext context) {
    final features = [
      (Icons.delivery_dining_rounded, s.groceryFastDelivery, s.groceryFastDeliveryHint),
      (Icons.sell_outlined, s.groceryBestPrices, s.groceryBestPricesHint),
      (Icons.eco_rounded, s.groceryFresh, s.groceryFreshHint),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        decoration: BoxDecoration(
          color: Gr.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Gr.line),
        ),
        child: Row(
          children: [
            for (final (icon, title, hint) in features)
              Expanded(
                child: Column(
                  children: [
                    Icon(icon, color: Gr.accent, size: 24),
                    const SizedBox(height: 6),
                    Text(title, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Gr.ink)),
                    const SizedBox(height: 2),
                    Text(hint, textAlign: TextAlign.center, maxLines: 2,
                        style: const TextStyle(fontSize: 10.5, color: Gr.ink3, height: 1.3)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The floating "view cart" pill above the nav (`.viewcart`, in grocery colours).
class _CartPill extends ConsumerWidget {
  const _CartPill({required this.token, required this.s});

  final String token;
  final Strings s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartForStoreProvider(token));
    return Material(
      color: Gr.accent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/s/$token/cart'),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Gr.onAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
                child: Text('${cart.count}', style: const TextStyle(fontWeight: FontWeight.w800, color: Gr.onAccent)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(s.viewCart, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Gr.onAccent)),
              ),
              RiyalPrice(amount: cart.total, size: 15, color: Gr.onAccent, decimals: 2),
            ],
          ),
        ),
      ),
    );
  }
}
