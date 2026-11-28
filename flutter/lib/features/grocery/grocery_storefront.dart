import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../menu/address_repository.dart';
import '../menu/cart_controller.dart';
import '../stores/data/store_repository.dart';
import '../stores/domain/menu.dart';
import '../stores/domain/storefront.dart';
import '../stores/presentation/store_avatar.dart';
import 'grocery_nav_bar.dart';
import 'grocery_product_card.dart';
import 'grocery_theme.dart';
import 'grocery_widgets.dart';

/// ============================================================================
/// THE SUPERMARKET HOME — Figma "Supermarket – Home v3 (Attractive)":
/// top bar (cart + bell | delivery location), greeting, search pill, hero
/// offer, "shop by category" tiles, "today's offers" with a countdown and
/// 2-column cards, then each category as its own section, under a floating
/// dark tab bar. Content is inset 20pt with 14pt between blocks.
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

  // The search pill scrolls in its natural place; once it would leave the
  // screen a docked copy (search + category chips) pins under the status bar.
  final _toolsSlot = GlobalKey();
  bool _slotMeasured = false;

  Storefront get store => widget.store;
  Strings get s => widget.s;
  Menu get menu => store.menu ?? const Menu(categories: [], uncategorised: []);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openCategory(int id) => context.push('/s/${widget.token}/category/$id');

  void _jumpTo(int categoryId) {
    AppHaptics.tick();
    final ctx = _sectionKeys[categoryId]?.currentContext;
    if (ctx == null) return _openCategory(categoryId);
    final box = ctx.findRenderObject();
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    if (box == null || viewport == null || !_scroll.hasClients) return;
    final target = (viewport.getOffsetToReveal(box, 0).offset - _dockedHeight(context) - 8)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target, duration: AppMotion.dur(context, AppMotion.slow), curve: AppMotion.curve);
  }

  double _dockedHeight(BuildContext context) =>
      MediaQuery.paddingOf(context).top + 4 + GrSearchPill.height + 10 + 34 + 10;

  double? _toolsScreenY() {
    final box = _toolsSlot.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null || !_scroll.hasClients) return null;
    return viewport.getOffsetToReveal(box, 0).offset - _scroll.offset;
  }

  Widget _stickyTools(BuildContext context, List<MenuCategory> categories) {
    final statusTop = MediaQuery.paddingOf(context).top;
    return AnimatedBuilder(
      animation: _scroll,
      builder: (context, _) {
        final y = _toolsScreenY();
        if (y == null) {
          if (!_slotMeasured) {
            _slotMeasured = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
          return const SizedBox.shrink();
        }
        if (y > statusTop + 4) return const SizedBox.shrink();
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Gr.bg,
            padding: EdgeInsets.fromLTRB(0, statusTop + 4, 0, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                  child: GrSearchPill(
                    hint: s.grocerySearchPlaceholder,
                    onTap: () => context.push('/s/${widget.token}/search'),
                    onFilter: () => context.push('/s/${widget.token}/categories'),
                  ),
                ),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                      itemCount: categories.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => GrChip(label: categories[i].name, onTap: () => _jumpTo(categories[i].id)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = menu.categories.where((c) => c.items.isNotEmpty).toList();
    final featured = menu.featured.where((i) => i.isAvailable).toList();
    final glyphOf = glyphByItem(menu);
    final promo = store.popups.isNotEmpty ? store.popups.first.image : store.cover;
    final cart = ref.watch(cartForStoreProvider(widget.token));

    // The hero's headline is the store's best live discount and its category.
    _Deal? deal;
    for (final c in menu.categories) {
      for (final i in c.items) {
        if (i.hasDiscount && i.isAvailable && (deal == null || i.discountPercent! > deal.percent)) {
          deal = _Deal(percent: i.discountPercent!, category: c);
        }
      }
    }

    final width = MediaQuery.sizeOf(context).width;
    final cellW = (width - Gr.pageX * 2 - 14) / 2;
    final cellH = GroceryProductCard.heightFor(cellW, GroceryCardStyle.minimal);

    SliverGrid grid(List<MenuItem> items) => SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 14,
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
        );

    const gap = _Gap(14);
    const sectionGap = _Gap(24);

    return ColoredBox(
      color: Gr.bg,
      child: Stack(
        children: [
          RefreshIndicator(
            color: Gr.primary,
            backgroundColor: Gr.surface,
            onRefresh: () async => ref.invalidate(storefrontProvider(widget.token)),
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(Gr.pageX, MediaQuery.paddingOf(context).top + 4, Gr.pageX, 0),
                  sliver: SliverList.list(children: [
                    _TopBar(store: store, s: s, token: widget.token, cartCount: cart.count),
                    const SizedBox(height: 14),
                    _Greeting(s: s),
                    const SizedBox(height: 14),
                    KeyedSubtree(
                      key: _toolsSlot,
                      child: GrSearchPill(
                        hint: s.grocerySearchPlaceholder,
                        onTap: () => context.push('/s/${widget.token}/search'),
                        onFilter: () => context.push('/s/${widget.token}/categories'),
                      ),
                    ),
                    if (promo != null && categories.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _HeroOffer(
                        image: promo,
                        deal: deal,
                        s: s,
                        onTap: () => _jumpTo((deal?.category ?? categories.first).id),
                      ),
                    ],
                  ]),
                ),
                if (categories.isNotEmpty) ...[
                  gap,
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                    sliver: SliverToBoxAdapter(
                      child: GrSectionHeader(
                        title: s.groceryShopByCategory,
                        onSeeAll: () => context.push('/s/${widget.token}/categories'),
                      ),
                    ),
                  ),
                  gap,
                  SliverToBoxAdapter(child: _CategoryTiles(categories: categories, onTap: _openCategory)),
                ],
                if (featured.isNotEmpty) ...[
                  sectionGap,
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                    sliver: SliverToBoxAdapter(
                      child: GrSectionHeader(
                        title: s.groceryTodayOffers,
                        leading: const GrCountdown(),
                        onSeeAll: () => context.push('/s/${widget.token}/category/featured'),
                      ),
                    ),
                  ),
                  const _Gap(12),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                    sliver: grid(featured.take(4).toList()),
                  ),
                ],
                for (final category in categories) ...[
                  sectionGap,
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                    sliver: SliverToBoxAdapter(
                      child: KeyedSubtree(
                        key: _sectionKeys.putIfAbsent(category.id, GlobalKey.new),
                        child: GrSectionHeader(title: category.name, onSeeAll: () => _openCategory(category.id)),
                      ),
                    ),
                  ),
                  const _Gap(12),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                    sliver: grid(category.items.take(4).toList()),
                  ),
                ],
                if (menu.uncategorised.isNotEmpty) ...[
                  sectionGap,
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                    sliver: SliverToBoxAdapter(child: GrSectionHeader(title: s.groceryAllProducts)),
                  ),
                  const _Gap(12),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                    sliver: grid(menu.uncategorised),
                  ),
                ],
                if (menu.isEmpty) ...[
                  const _Gap(48),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const Icon(Icons.shopping_basket_outlined, color: Gr.ink3, size: 40),
                        const SizedBox(height: 12),
                        Text(s.menuEmpty, style: Gr.text(14, weight: 600, color: Gr.ink2)),
                      ],
                    ),
                  ),
                ],
                _Gap(groceryBottomClearance(context, hasCart: !cart.isEmpty)),
              ],
            ),
          ),
          _stickyTools(context, categories),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!cart.isEmpty) ...[
                  GroceryCartBar(token: widget.token),
                  const SizedBox(height: 12),
                ],
                GroceryNavBar(token: widget.token, active: GroceryTab.home),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap(this.height);

  final double height;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(child: SizedBox(height: height));
}

class _Deal {
  const _Deal({required this.percent, required this.category});

  final int percent;
  final MenuCategory category;
}

// ---------------------------------------------------------------------------

/// Figma "Top Bar": the delivery-location pill on the start side, the dark
/// cart button (lime count badge) and the white bell on the end side.
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.store, required this.s, required this.token, required this.cartCount});

  final Storefront store;
  final Strings s;
  final String token;
  final int cartCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressesProvider).asData?.value ?? const <CustomerAddress>[];
    final address = addresses.where((a) => a.isDefault).firstOrNull ?? addresses.firstOrNull;
    final location = address == null
        ? s.groceryChooseLocation
        : (address.addressText.trim().isNotEmpty ? address.addressText : address.label);

    return Row(
      children: [
        // Location pill (Figma "Location").
        Flexible(
          child: GestureDetector(
            onTap: () => context.push('/addresses'),
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Gr.surface,
                borderRadius: BorderRadius.circular(Gr.pill),
                boxShadow: Gr.pillShadow,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GrIcon('pin', size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis, style: Gr.text(13, weight: 600)),
                  ),
                  const SizedBox(width: 6),
                  const GrIcon('chevron_down', size: 14),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        GrCircleButton(icon: 'bell', onTap: () => context.push('/notifications'), semanticLabel: s.notifications),
        const SizedBox(width: 8),
        GrCircleButton(
          icon: 'cart',
          dark: true,
          badge: cartCount,
          onTap: () => context.push('/s/$token/cart'),
          semanticLabel: s.cart,
        ),
      ],
    );
  }
}

/// Figma "Greeting": a grey time-of-day line and the 26pt question.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.s});

  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(groceryGreeting(s), style: Gr.text(14, color: Gr.ink2)),
        Text(s.groceryWhatToday, style: Gr.text(26, weight: 800, height: 1.2)),
      ],
    );
  }
}

/// Figma "Hero Offer": the merchant's photo under a dark-green wash that
/// deepens towards the text side; a lime tag, a two-line headline from the
/// store's best live discount, and a lime "order now" pill.
class _HeroOffer extends StatelessWidget {
  const _HeroOffer({required this.image, required this.deal, required this.s, required this.onTap});

  final String image;
  final _Deal? deal;
  final Strings s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line1 = deal != null ? s.groceryPromoUpTo(deal!.percent) : s.groceryPromoFreshTitle;
    final line2 = deal != null ? s.groceryPromoOn(deal!.category.name) : s.groceryHeroHint;

    return Container(
      height: 176,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(Gr.rHero), boxShadow: Gr.heroShadow),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AppImage(url: logoUrlOf(image), fit: BoxFit.cover, placeholderColor: Gr.primary, error: const ColoredBox(color: Gr.primary)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerEnd,
                end: AlignmentDirectional.centerStart,
                stops: const [0, 0.42, 0.75, 1],
                colors: [
                  Gr.primary.withValues(alpha: 0),
                  Gr.primary.withValues(alpha: 0.15),
                  Gr.primary.withValues(alpha: 0.9),
                  Gr.primary,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(22, 14, 16, 14),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(color: Gr.lime, borderRadius: BorderRadius.circular(Gr.pill)),
                      child: Text(s.groceryOfferTag, style: Gr.text(11, weight: 700, color: Gr.onLime)),
                    ),
                    const SizedBox(height: 10),
                    Text(line1, maxLines: 1, overflow: TextOverflow.ellipsis, style: Gr.text(22, weight: 800, color: Colors.white, height: 1.25)),
                    Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis, style: Gr.text(22, weight: 800, color: Colors.white, height: 1.25)),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(color: Gr.lime, borderRadius: BorderRadius.circular(Gr.pill)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const GrIcon('arrow_cta', size: 16, flipForRtl: true),
                            const SizedBox(width: 6),
                            Text(s.groceryOrderNow, style: Gr.text(13, weight: 700, color: Gr.onLime)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Figma "Category Tiles": five tiles spread across the width; more than five
/// scroll horizontally with the same spacing.
class _CategoryTiles extends StatelessWidget {
  const _CategoryTiles({required this.categories, required this.onTap});

  final List<MenuCategory> categories;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    if (categories.length <= 5) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final c in categories) GrCategoryTile(category: c, onTap: () => onTap(c.id)),
          ],
        ),
      );
    }
    return SizedBox(
      height: 64 + 8 + 20,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => GrCategoryTile(category: categories[i], onTap: () => onTap(categories[i].id)),
      ),
    );
  }
}
