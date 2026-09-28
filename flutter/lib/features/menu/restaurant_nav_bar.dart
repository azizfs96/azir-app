import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import 'cart_controller.dart';

/// The restaurant template's bottom navigation (Jahez-style): home, cart (with a
/// live count), orders and account. Shown only inside a restaurant storefront,
/// where the store token is known; the active tab is painted as a dark pill.
enum NavTab { home, cart, orders, account }

class RestaurantNavBar extends ConsumerWidget {
  const RestaurantNavBar({super.key, required this.token, required this.active});

  final String token;
  final NavTab active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final count = ref.watch(cartForStoreProvider(token)).count;

    void go(NavTab tab) {
      if (tab == active) return;
      switch (tab) {
        case NavTab.home:
          context.go('/s/$token');
        case NavTab.cart:
          context.push('/s/$token/cart');
        case NavTab.orders:
          context.push('/orders');
        case NavTab.account:
          context.push('/profile');
      }
    }

    // No solid bar: each tab floats on the page (Jahez-style). A soft gradient
    // fades the menu into the cream canvas behind the tabs, so dishes that
    // scroll under them blur away rather than clash with the icons.
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.55, 1],
          colors: [Color(0x00F6F3EE), Color(0xE6F6F3EE), Color(0xFFF6F3EE)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Item(
                icon: Icons.home_rounded,
                label: s.homeTab,
                selected: active == NavTab.home,
                onTap: () => go(NavTab.home),
              ),
              _Item(
                icon: Icons.shopping_bag_outlined,
                label: s.cart,
                selected: active == NavTab.cart,
                badge: count,
                onTap: () => go(NavTab.cart),
              ),
              _Item(
                // A ticket/coupon glyph, as the reference uses for orders.
                icon: Icons.confirmation_number_outlined,
                label: s.myOrders,
                selected: active == NavTab.orders,
                onTap: () => go(NavTab.orders),
              ),
              _Item(
                icon: Icons.person_outline_rounded,
                label: s.myAccount,
                selected: active == NavTab.account,
                onTap: () => go(NavTab.account),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final Widget content = selected
        // Active: a dark pill with the icon + label.
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.ink900,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: Colors.white),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
          )
        // Inactive: a floating white circle with the icon.
        : Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Icon(icon, size: 23, color: AppColors.ink700),
          );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: badge > 0
          ? Badge(
              label: Text('$badge'),
              backgroundColor: AppColors.flame,
              child: content,
            )
          : content,
    );
  }
}
