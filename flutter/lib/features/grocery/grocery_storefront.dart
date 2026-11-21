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
import 'category_glyph.dart';
import 'grocery_nav_bar.dart';
import 'grocery_product_card.dart';
import 'grocery_theme.dart';

/// ============================================================================
/// THE SUPERMARKET STOREFRONT — the grocery home from the design reference:
/// a pale-green canvas, a greeting + hero line beside the store's photo, a
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
    // Category glyph per item id, for products without a photo.
    final glyphOf = <int, String>{
      for (final c in menu.categories)
        for (final i in c.items) i.id: categoryGlyph(c.name),
    };
    final promo = store.popups.isNotEmpty ? store.popups.first.image : store.cover;
    final cart = ref.watch(cartForStoreProvider(widget.token));
    // One cell width for every product tile on the page (grid and best
    // sellers); each section's row height follows its longest name.
    final cellW = Gr.homeCellWidth(MediaQuery.sizeOf(context).width);
    double heightFor(Iterable<MenuItem> items) => GroceryProductCard.heightFor(
          cellW,
          nameLines: GroceryProductCard.nameLinesFor(context, items, cellW),
        );
    // Clearance under the last section: 32 to the nav bar, the bar itself, its
    // safe area, and the floating cart pill when there is one.
    final bottomClearance = Gr.s24 +
        GroceryNavBar.height +
        MediaQuery.paddingOf(context).bottom +
        (cart.isEmpty ? 0 : _CartPill.height + Gr.s16);

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
                // Vertical rhythm (8pt grid, reference density): header ─16─
                // search ─16─ categories ─16─ promo ─24─ best sellers ─24─ each
                // category (title ─12─ grid) ─24─ features card ─24─ nav bar.
                SliverToBoxAdapter(child: _Header(store: store, s: s, token: widget.token, onShare: widget.onShare)),
                const _Gap(Gr.s16),
                SliverToBoxAdapter(child: _SearchField(token: widget.token, s: s)),
                if (categories.isNotEmpty) ...[
                  const _Gap(Gr.s16),
                  SliverToBoxAdapter(child: _CategoryStrip(categories: categories, onTap: _jumpTo)),
                ],
                if (promo != null) ...[
                  const _Gap(Gr.s16),
                  SliverToBoxAdapter(
                    child: _PromoBanner(
                      image: promo,
                      s: s,
                      onTap: () => categories.isEmpty ? null : _jumpTo(categories.first.id),
                    ),
                  ),
                ],
                if (featured.isNotEmpty) ...[
                  const _Gap(Gr.s24),
                  SliverToBoxAdapter(
                    child: _SectionTitle(
                      title: s.groceryBestSellers,
                      action: s.seeAll,
                      onAction: () => context.push('/s/${widget.token}/categories?featured=1'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: heightFor(featured),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                        itemCount: featured.length,
                        separatorBuilder: (_, _) => const SizedBox(width: Gr.s12),
                        itemBuilder: (_, i) => GroceryProductCard(
                          token: widget.token,
                          item: featured[i],
                          s: s,
                          width: cellW,
                          fallbackGlyph: glyphOf[featured[i].id] ?? '🛒',
                        ),
                      ),
                    ),
                  ),
                ],
                for (final category in categories) ...[
                  const _Gap(Gr.s24),
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
                  _ProductGrid(
                    token: widget.token,
                    items: category.items,
                    s: s,
                    glyph: categoryGlyph(category.name),
                    cellHeight: heightFor(category.items),
                  ),
                ],
                if (menu.uncategorised.isNotEmpty) ...[
                  const _Gap(Gr.s24),
                  SliverToBoxAdapter(child: _SectionTitle(title: s.groceryAllProducts)),
                  _ProductGrid(
                    token: widget.token,
                    items: menu.uncategorised,
                    s: s,
                    cellHeight: heightFor(menu.uncategorised),
                  ),
                ],
                if (menu.isEmpty) ...[
                  const _Gap(Gr.s48),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const Icon(Icons.shopping_basket_outlined, color: Gr.ink3, size: 40),
                        const SizedBox(height: Gr.s12),
                        Text(s.menuEmpty, style: const TextStyle(color: Gr.ink2, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
                const _Gap(Gr.s24),
                SliverToBoxAdapter(child: _FeaturesRow(s: s)),
                // Room so the nav bar and the floating cart pill never cover content.
                _Gap(bottomClearance),
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
                  padding: const EdgeInsets.fromLTRB(Gr.headerX, 0, Gr.headerX, GroceryNavBar.height + Gr.s12),
                  child: _CartPill(token: widget.token, s: s),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A vertical gap between slivers, always one of the [Gr] spacing steps.
class _Gap extends StatelessWidget {
  const _Gap(this.height);

  final double height;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(child: SizedBox(height: height));
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
      padding: EdgeInsets.fromLTRB(Gr.headerX, top + Gr.s8, Gr.headerX, 0),
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
              const SizedBox(width: Gr.s8),
              StoreAvatar(name: store.name, logoPath: store.logo, brandColor: store.brandColor, size: 32),
              const SizedBox(width: Gr.s8),
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
                const SizedBox(width: Gr.s8),
              ],
              _RoundIcon(icon: Icons.notifications_none_rounded, onTap: () => context.push('/notifications')),
            ],
          ),
          const SizedBox(height: Gr.s16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.groceryWelcome, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Gr.accent)),
                    const SizedBox(height: Gr.s4),
                    Text(
                      s.groceryHeroTitle,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Gr.ink, height: 1.15),
                    ),
                    Text(
                      s.groceryHeroAccent,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Gr.accent, height: 1.15),
                    ),
                    const SizedBox(height: Gr.s8),
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
                const SizedBox(width: Gr.s12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(Gr.s16),
                  child: SizedBox(
                    width: 112,
                    height: 112,
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
          width: 40,
          height: 40,
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
      padding: const EdgeInsets.symmetric(horizontal: Gr.headerX),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Gr.surface2,
              borderRadius: BorderRadius.circular(Gr.cardRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(Gr.cardRadius),
                onTap: () => context.push('/s/$token/search'),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: Gr.s12),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: Gr.ink3, size: 20),
                      const SizedBox(width: Gr.s8),
                      Text(s.grocerySearchHint, style: const TextStyle(color: Gr.ink3, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Gr.s8),
          Material(
            color: Gr.accent,
            borderRadius: BorderRadius.circular(Gr.cardRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(Gr.cardRadius),
              onTap: () => context.push('/s/$token/categories'),
              child: const SizedBox(width: 44, height: 44, child: Icon(Icons.tune_rounded, color: Gr.onAccent, size: 20)),
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
    // 60 chip + 8 + two label lines (11.5 × 1.2 × 2 ≈ 28) = 96.
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gr.s8),
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
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Gr.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: i == 0 ? Gr.accent : Gr.line, width: 1.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: c.image != null
                        ? AppImage(url: logoUrlOf(c.image), placeholderColor: Gr.surface2, error: _CategoryGlyph(c.name))
                        : _CategoryGlyph(c.name),
                  ),
                  const SizedBox(height: Gr.s8),
                  Expanded(
                    child: Text(
                      c.name,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Gr.ink2, height: 1.2),
                    ),
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

/// The category's emoji, large and centred — Apple's colour artwork on iOS
/// reads as a real product photo at this size.
class _CategoryGlyph extends StatelessWidget {
  const _CategoryGlyph(this.name);

  final String name;

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(categoryGlyph(name), style: const TextStyle(fontSize: 28, height: 1)));
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.image, required this.s, required this.onTap});

  final String image;
  final Strings s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Gr.cardRadius),
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
                padding: const EdgeInsets.all(Gr.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(s.groceryPromoKicker.toUpperCase(),
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Gr.accent, letterSpacing: 0.6)),
                    const SizedBox(height: Gr.s4),
                    Text(s.groceryHeroHint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Gr.ink, height: 1.25)),
                    const SizedBox(height: Gr.s12),
                    Material(
                      color: Gr.accent,
                      borderRadius: BorderRadius.circular(99),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Gr.s12, vertical: Gr.s8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(s.shopNow, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Gr.onAccent)),
                              const SizedBox(width: Gr.s4),
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
    // The section gap above comes from the page rhythm; 12 below to the products.
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gr.pageX, 0, Gr.pageX, Gr.s12),
      child: Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Gr.ink))),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Gr.accent)),
                  const SizedBox(width: Gr.s4),
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
  const _ProductGrid({
    required this.token,
    required this.items,
    required this.s,
    required this.cellHeight,
    this.glyph = '🛒',
  });

  final String token;
  final List<MenuItem> items;
  final Strings s;
  final String glyph;

  /// From [GroceryProductCard.heightFor] of the cell width — every row equal.
  final double cellHeight;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
      sliver: SliverGrid(
        // Three across on the home page (the reference layout); the cell width
        // follows from the screen width, the two 20pt margins and 12pt gutters.
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: Gr.homeColumns,
          mainAxisSpacing: Gr.s16,
          crossAxisSpacing: Gr.s12,
          mainAxisExtent: cellHeight,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => GroceryProductCard(token: token, item: items[i], s: s, fallbackGlyph: glyph),
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
      padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Gr.s8, vertical: Gr.s12),
        decoration: BoxDecoration(
          color: Gr.surface,
          borderRadius: BorderRadius.circular(Gr.cardRadius),
          border: Border.all(color: Gr.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (icon, title, hint) in features)
              Expanded(
                child: Column(
                  children: [
                    Icon(icon, color: Gr.accent, size: 24),
                    const SizedBox(height: Gr.s8),
                    Text(title, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Gr.ink)),
                    const SizedBox(height: Gr.s4),
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

  static const height = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartForStoreProvider(token));
    return Material(
      color: Gr.accent,
      borderRadius: BorderRadius.circular(Gr.s16),
      child: InkWell(
        borderRadius: BorderRadius.circular(Gr.s16),
        onTap: () => context.push('/s/$token/cart'),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: Gr.s16),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Gr.onAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(Gr.s8)),
                child: Text('${cart.count}', style: const TextStyle(fontWeight: FontWeight.w800, color: Gr.onAccent)),
              ),
              const SizedBox(width: Gr.s12),
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
