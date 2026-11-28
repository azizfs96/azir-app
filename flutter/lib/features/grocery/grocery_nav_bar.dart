import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../menu/cart_controller.dart';
import 'grocery_theme.dart';

/// The design's floating tab bar (Figma "Floating Tab Bar"): a dark-green pill
/// 68pt tall inset 20pt from the sides, four 52pt icon circles and the active
/// tab as a lime pill carrying its label and icon. Home · Categories · Cart ·
/// Orders · Account.
enum GroceryTab { home, categories, cart, orders, account }

class GroceryNavBar extends ConsumerWidget {
  const GroceryNavBar({super.key, required this.token, required this.active});

  final String token;
  final GroceryTab active;

  /// Bar height; screens add this + [bottomInset] to their content padding.
  static const height = Gr.tabBarHeight;

  /// Space under the bar: the home indicator inset plus 4pt (design: 38 on a
  /// 34pt inset).
  static double bottomInset(BuildContext context) => MediaQuery.paddingOf(context).bottom + 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final count = ref.watch(cartForStoreProvider(token)).count;

    void go(GroceryTab tab) {
      if (tab == active) return;
      AppHaptics.tick();
      switch (tab) {
        case GroceryTab.home:
          context.go('/s/$token');
        case GroceryTab.categories:
          context.push('/s/$token/categories');
        case GroceryTab.cart:
          context.push('/s/$token/cart');
        case GroceryTab.orders:
          context.push('/orders');
        case GroceryTab.account:
          context.push('/profile');
      }
    }

    final items = [
      (GroceryTab.home, 'tab_home', s.homeTab),
      (GroceryTab.categories, 'tab_grid', s.categoriesTab),
      (GroceryTab.cart, 'tab_cart', s.cart),
      (GroceryTab.orders, 'tab_receipt', s.myOrders),
      (GroceryTab.account, 'tab_user', s.myAccount),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(Gr.pageX, 0, Gr.pageX, bottomInset(context)),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: Gr.primary,
          borderRadius: BorderRadius.circular(Gr.pill),
          boxShadow: Gr.barShadow,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final (tab, icon, label) in items)
              if (tab == active)
                // The lime pill yields first when the bar is narrow.
                Flexible(child: _Tab(icon: icon, label: label, selected: true, onTap: () => go(tab)))
              else
                _Tab(
                  icon: icon,
                  label: label,
                  selected: false,
                  badge: tab == GroceryTab.cart ? count : 0,
                  onTap: () => go(tab),
                ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.selected, required this.onTap, this.badge = 0});

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final child = selected
        ? Container(
            key: const ValueKey('active'),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(color: Gr.lime, borderRadius: BorderRadius.circular(Gr.pill)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GrIcon(icon, size: 24, color: Gr.onLime),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Gr.text(13, weight: 700, color: Gr.onLime),
                  ),
                ),
              ],
            ),
          )
        : SizedBox(
            key: const ValueKey('idle'),
            width: 52,
            height: 52,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                GrIcon(icon, size: 24, color: Colors.white.withValues(alpha: 0.65)),
                if (badge > 0)
                  PositionedDirectional(
                    top: 8,
                    end: 6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Gr.lime, borderRadius: BorderRadius.circular(8)),
                      child: Text('$badge', style: Gr.text(9, weight: 800, color: Gr.onLime, height: 1)),
                    ),
                  ),
              ],
            ),
          );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedSwitcher(duration: AppMotion.dur(context, AppMotion.fast), child: child),
      ),
    );
  }
}

/// The design's "View Cart Bar": a dark pill with the cart icon and count on
/// the start side and the total in a lime pill on the end side. Shown above
/// the tab bar (or alone on product pages) whenever the cart has lines.
class GroceryCartBar extends ConsumerWidget {
  const GroceryCartBar({super.key, required this.token});

  final String token;

  static const height = Gr.cartBarHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final cart = ref.watch(cartForStoreProvider(token));
    if (cart.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
      child: Material(
        color: Gr.primary,
        borderRadius: BorderRadius.circular(Gr.pill),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(Gr.pill),
          onTap: () => context.push('/s/$token/cart'),
          child: Container(
            height: height,
            padding: const EdgeInsetsDirectional.only(start: 18, end: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(Gr.pill), boxShadow: Gr.barShadow),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned(left: 4, top: 4, child: GrIcon('tab_cart', size: 24, color: Colors.white)),
                      PositionedDirectional(
                        end: -4,
                        top: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: Gr.lime, borderRadius: BorderRadius.circular(8)),
                          child: Text('${cart.count}', style: Gr.text(9, weight: 800, color: Gr.onLime, height: 1)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(s.viewCart, style: Gr.text(15, weight: 700, color: Colors.white, height: 1.2)),
                      Text(
                        s.groceryItemsCount(cart.count),
                        style: Gr.text(11, color: Colors.white.withValues(alpha: 0.7), height: 1.2),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(color: Gr.lime, borderRadius: BorderRadius.circular(Gr.pill)),
                  child: Text(Gr.price(cart.total, s.sar), style: Gr.text(15, weight: 800, color: Gr.onLime, height: 1.25)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Total clearance a scrolling screen leaves under its last row so the cart
/// bar and the tab bar never cover content.
double groceryBottomClearance(BuildContext context, {required bool hasCart, bool withTabBar = true}) =>
    GroceryNavBar.bottomInset(context) +
    (withTabBar ? GroceryNavBar.height : 0) +
    (hasCart ? GroceryCartBar.height + 12 : 0) +
    24;
