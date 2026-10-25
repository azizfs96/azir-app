import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/skeleton.dart';
import '../../booking/data/store_bookings_provider.dart';
import '../../home/data/my_stores_repository.dart';
import '../data/store_repository.dart';
import '../domain/storefront.dart';
import '../../menu/cart_screen.dart';
import '../../menu/menu_view.dart';
import '../../menu/restaurant_header.dart';
import '../../menu/restaurant_nav_bar.dart';
import '../domain/menu.dart';
import 'store_avatar.dart';
import 'store_popup.dart';
import 'storefront_bookings.dart';
import 'store_locations_sheet.dart';
import 'storefront_header.dart';
import 'storefront_states.dart';

/// ============================================================================
/// THE MERCHANT STOREFRONT (spec §8, §31)
///
/// Cover · logo · identity · hours + location · book · services, with the
/// customer's own history at this merchant behind a second tab.
///
/// Every pixel comes from the API payload. The merchant is not a separate
/// application — it is a dynamic experience inside Wasla, and adding a merchant
/// never requires a new build (§43).
/// ============================================================================
class StorefrontScreen extends ConsumerStatefulWidget {
  const StorefrontScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends ConsumerState<StorefrontScreen> {
  @override
  void initState() {
    super.initState();
    // Opening a store adds it to My Stores (spec §6). Fire-and-forget: the
    // storefront must render whether or not the customer is signed in yet.
    WidgetsBinding.instance.addPostFrameCallback((_) => _addToMyStores());
  }

  Future<void> _addToMyStores() async {
    try {
      await ref.read(myStoresRepositoryProvider).add(widget.token);
      ref.invalidate(myStoresProvider);
    } catch (_) {
      // Unauthenticated browsing is expected — the store is added on sign-in.
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final store = ref.watch(storefrontProvider(widget.token));

    // The restaurant template gets a warm canvas; its Jahez-style bottom nav
    // floats OVER the menu (added in _StoreView), so the dishes scroll behind it.
    final isRestaurant = store.value?.isRestaurant ?? false;

    return Scaffold(
      backgroundColor: isRestaurant ? Ds.bg : Colors.white,
      body: store.when(
        loading: () => const _MenuSkeleton(),
        /*
         * A connection failure is NOT "no such store". Conflating them told a
         * customer their merchant's printed code was invalid when the real
         * problem was the network.
         */
        error: (error, _) => ApiFailure.from(error).isStoreNotFound
            ? StorefrontNotFound(s: s)
            : StorefrontUnreachable(
                s: s,
                onRetry: () => ref.invalidate(storefrontProvider(widget.token)),
              ),
        data: (data) => _StoreView(store: data, s: s, token: widget.token),
      ),
    );
  }
}

/// Loading placeholder shaped like the storefront (banner, filter chips, dish
/// grid) so the real menu swaps in without a jarring blank-to-content jump.
class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: const [
                SkeletonBox(width: 130, height: 22, radius: 7),
                Spacer(),
                SkeletonBox(width: 40, height: 40, radius: 20),
              ],
            ),
            const SizedBox(height: 16),
            const SkeletonBox(height: 150, radius: 20),
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  const SkeletonBox(width: 72, height: 34, radius: 18),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 18),
            for (var r = 0; r < 2; r++)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 180, radius: 16, color: Colors.white)),
                    SizedBox(width: 12),
                    Expanded(child: SkeletonBox(height: 180, radius: 16, color: Colors.white)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StoreView extends ConsumerStatefulWidget {
  const _StoreView({required this.store, required this.s, required this.token});

  final Storefront store;
  final Strings s;
  final String token;

  @override
  ConsumerState<_StoreView> createState() => _StoreViewState();
}

class _StoreViewState extends ConsumerState<_StoreView> {
  int _tab = 0;

  // ---- the sticky category chips (restaurant) --------------------------------
  // The chip row scrolls in its natural place; this copy follows it and pins
  // under the status bar once it would scroll out — the design's `.menu-bar`
  // `position: sticky; top: var(--top)` with the `.topcover` backdrop.
  final _scroll = ScrollController();
  final _chipsSlot = GlobalKey();
  final Map<String, GlobalKey> _anchors = {};
  int _activeChip = 0;
  bool _slotMeasured = false;

  @override
  void initState() {
    super.initState();
    // The merchant's pop-up ad, shown once the storefront is on screen (the
    // helper decides whether one is due for this device).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowStorePopups(context, widget.store);
    });
  }

  GlobalKey _anchorFor(String id) => _anchors.putIfAbsent(id, GlobalKey.new);

  void _onChipTap(int index, String id) {
    setState(() => _activeChip = index);
    jumpToMenuSection(_anchors[id]);
  }

  /// Where the in-flow chip row's top edge currently sits, relative to the
  /// scroll view's top edge; null until it has been laid out.
  double? _chipsScreenY() {
    final box = _chipsSlot.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null || !_scroll.hasClients) return null;
    return viewport.getOffsetToReveal(box, 0).offset - _scroll.offset;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The sticky copy of the chip row. It sits exactly over the in-flow row while
  /// that row is on screen, then stops under the status bar and stays there
  /// (with a canvas-coloured backdrop over the status bar) as the menu scrolls
  /// beneath — `.menu-bar{position:sticky}` + `.topcover`.
  Widget _stickyChips(BuildContext context) {
    final menu = store.menu;
    if (menu == null || menu.isEmpty) return const SizedBox.shrink();
    final sections = menuSections(menu, s);
    if (sections.isEmpty) return const SizedBox.shrink();

    // Once docked, the chips sit under a compact header (back / name / actions)
    // that stays with them — so the store identity and the actions never
    // scroll away. The chips therefore pin below status bar + header.
    final statusTop = MediaQuery.paddingOf(context).top;
    final stickTop = statusTop + StoreTopBar.height;
    final topBar = StoreTopBar(
      store: store,
      s: s,
      onSearch: () => context.push('/s/${widget.token}/search'),
      onNotifications: () => context.push('/notifications'),
      onShare: _share,
      onBack: context.canPop() ? () => context.pop() : null,
    );

    return AnimatedBuilder(
      animation: _scroll,
      builder: (context, _) {
        final y = _chipsScreenY();
        if (y == null) {
          // First frame: the row isn't laid out yet — measure once it is.
          if (!_slotMeasured) {
            _slotMeasured = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
          }
          return const SizedBox.shrink();
        }
        final pinned = y <= stickTop;
        final bar = MenuChipBar(
          titles: [for (final sec in sections) sec.title],
          active: _activeChip.clamp(0, sections.length - 1),
          brand: brand,
          onTap: (i) => _onChipTap(i, sections[i].id),
        );
        return Positioned(
          top: pinned ? 0 : y,
          left: 0,
          right: 0,
          child: pinned
              ? ColoredBox(
                  color: Ds.bg,
                  child: Padding(
                    padding: EdgeInsets.only(top: statusTop),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [topBar, bar],
                    ),
                  ),
                )
              : bar,
        );
      },
    );
  }

  Storefront get store => widget.store;
  Strings get s => widget.s;
  Color get brand => brandColorOf(store.brandColor);

  void _share() {
    final link = store.deepLink;
    if (link == null) return;

    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.copied), behavior: SnackBarBehavior.floating),
    );
  }

  /*
   * "الموقع" tapped.
   *
   * One destination opens immediately; several (a multi-branch merchant)
   * raise a chooser naming each branch with its address. The tap used to be
   * wired to nothing at all — the header exposed onOpenMap and no screen
   * ever passed it.
   */
  Future<void> _openLocation(BuildContext context) =>
      openStoreLocations(context, store: store, s: s, brand: brand);

  /// No service preselected — the flow opens on its first step, which the
  /// server decided (branch or service, depending on the merchant).
  void _book() => context.push('/s/${store.token}/book');

  @override
  Widget build(BuildContext context) {
    final header = SliverToBoxAdapter(
      child: StorefrontHeader(
        store: store,
        s: s,
        brand: brand,
        onShare: _share,
        onOpenMap: () => _openLocation(context),
      ),
    );

    // A restaurant browses a menu and builds a cart; a salon books an
    // appointment. Same screen shell, two journeys chosen by the engine.
    final scroll = CustomScrollView(
      controller: store.isRestaurant ? _scroll : null,
      slivers: store.isRestaurant
          ? [
              // The cover photo is tall and the header climbs into its faded
              // bottom, so the photo dissolves *behind* the mode bar rather
              // than stopping at a line above it (the TikTok-profile blend).
              SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final coverHeight = c.maxWidth / kCoverAspect;
                    return Stack(
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: coverHeight,
                          child: StoreCover(
                            store: store,
                            s: s,
                            brand: brand,
                            onSearch: () => context.push('/s/${widget.token}/search'),
                            onNotifications: () => context.push('/notifications'),
                            onShare: _share,
                            onBack: context.canPop() ? () => context.pop() : null,
                          ),
                        ),
                        Column(
                          children: [
                            SizedBox(height: coverHeight - kCoverOverlap),
                            RestaurantHeader(store: store, s: s, brand: brand),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
              MenuView(
                storeToken: widget.token,
                menu: store.menu ?? const Menu(categories: [], uncategorised: []),
                brand: brand,
                s: s,
                prepMinutes: store.configuration.defaultPrepMinutes,
                chipsSlotKey: _chipsSlot,
                activeChip: _activeChip,
                onChipTap: _onChipTap,
                anchorFor: _anchorFor,
              ),
              // Room so the floating cart bar + nav never hide the last dish.
              const SliverToBoxAdapter(child: SizedBox(height: 140)),
            ]
          : [
              header,
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: store.services.isEmpty ? null : _book,
                      style: FilledButton.styleFrom(
                        backgroundColor: brand,
                        disabledBackgroundColor: AppColors.ink200,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        s.bookAppointment,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
                  child: _Tabs(
                    s: s,
                    current: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ),
              ),
              if (_tab == 0)
                _ServicesSliver(store: store, s: s, brand: brand)
              else
                StorefrontBookingsSliver(token: widget.token, s: s),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(storefrontProvider(widget.token));
        ref.invalidate(storeBookingsProvider(widget.token));
      },
      // The design canvas with the bottom nav and the "view cart" bar FLOATING
      // over the menu, so the dishes scroll behind them.
      child: store.isRestaurant
          ? ColoredBox(
              color: Ds.bg,
              child: Stack(
                children: [
                  scroll,
                  _stickyChips(context),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: RestaurantNavBar(token: widget.token, active: NavTab.home, brand: brand),
                  ),
                  // `.viewcart`: 14px in from the sides, sitting above the nav.
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 19),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 82),
                        child: CartBar(token: widget.token, brand: brand),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : scroll,
    );
  }
}

/// Segmented control rather than a TabBar: the header scrolls away with the
/// content, and a pinned tab bar over a photo header fights the scroll.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.s, required this.current, required this.onChanged});

  final Strings s;
  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = [s.popularServices, s.myBookingsTab];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.ink100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: i == current ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                      color: i == current ? AppColors.ink900 : AppColors.ink500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ServicesSliver extends StatelessWidget {
  const _ServicesSliver({required this.store, required this.s, required this.brand});

  final Storefront store;
  final Strings s;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    if (store.services.isEmpty) {
      return SliverToBoxAdapter(
        child: StorefrontPlaceholder(icon: Icons.spa_outlined, title: s.noServices),
      );
    }

    return SliverPadding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 0),
      sliver: SliverList.separated(
        itemCount: store.services.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.ink100),
        itemBuilder: (context, i) => _ServiceRow(
          service: store.services[i],
          store: store,
          s: s,
          brand: brand,
        ),
      ),
    );
  }
}

/// One service: icon tile · name · duration and price · chevron.
///
/// The whole row is the tap target — a per-row button would be noise when
/// booking is the only thing to do here.
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.service,
    required this.store,
    required this.s,
    required this.brand,
  });

  final StoreService service;
  final Storefront store;
  final Strings s;
  final Color brand;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/s/${store.token}/book', extra: service),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: brand.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.content_cut_rounded, size: 20, color: brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    service.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // Duration first: it decides whether the appointment fits
                    // someone's day, before the price does.
                    '${s.minutes(service.durationMinutes)}  ·  '
                    '${s.fromPrice('${_money(service.price)} ${s.currency}')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.ink500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.ink300),
          ],
        ),
      ),
    );
  }

  static String _money(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}
