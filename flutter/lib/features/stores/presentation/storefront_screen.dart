import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/strings.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../booking/data/store_bookings_provider.dart';
import '../../home/data/my_stores_repository.dart';
import '../data/store_repository.dart';
import '../domain/storefront.dart';
import '../../menu/menu_view.dart';
import '../../menu/restaurant_header.dart';
import '../../menu/restaurant_nav_bar.dart';
import '../domain/menu.dart';
import 'store_avatar.dart';
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
      backgroundColor: isRestaurant ? AppColors.cream : Colors.white,
      body: store.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
      slivers: store.isRestaurant
          ? [
              RestaurantTopBar(
                store: store,
                onShare: _share,
                onSearch: () => context.push('/s/${widget.token}/search'),
                onBack: context.canPop() ? () => context.pop() : null,
              ),
              SliverToBoxAdapter(
                child: RestaurantHeader(
                  store: store,
                  s: s,
                  brand: brand,
                  onOrderNow: () {},
                ),
              ),
              MenuView(
                storeToken: widget.token,
                menu: store.menu ?? const Menu(categories: [], uncategorised: []),
                brand: brand,
                s: s,
                prepMinutes: store.configuration.defaultPrepMinutes,
              ),
              // Room so the floating cart bar never hides the last dish.
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
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
      // A warm cream canvas with the bottom nav FLOATING over the menu, so the
      // dishes scroll behind the tabs (Jahez-style).
      child: store.isRestaurant
          ? ColoredBox(
              color: AppColors.cream,
              child: Stack(
                children: [
                  scroll,
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: RestaurantNavBar(token: widget.token, active: NavTab.home),
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
