import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bump.dart';
import 'cart_controller.dart';

/// The design system's bottom navigation (`.nav`): a floating frosted pill bar
/// holding four round tabs — home, cart (with a live count), orders, account.
/// The active tab stretches into a brand-coloured pill with its label.
enum NavTab { home, cart, orders, account }

class RestaurantNavBar extends ConsumerWidget {
  const RestaurantNavBar({
    super.key,
    required this.token,
    required this.active,
    this.brand = AppColors.ink900,
  });

  final String token;
  final NavTab active;
  final Color brand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = Strings.of(context);
    final count = ref.watch(cartForStoreProvider(token)).count;

    void go(NavTab tab) {
      if (tab == active) return;
      AppHaptics.tick();
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

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 19),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Ds.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Ds.line.withValues(alpha: 0.7)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Item(
                    icon: Icons.home_rounded,
                    label: s.homeTab,
                    selected: active == NavTab.home,
                    brand: brand,
                    onTap: () => go(NavTab.home),
                  ),
                  // The cart tab pulses whenever the count rises (added to cart).
                  Bump(
                    value: count,
                    child: _Item(
                      icon: Icons.shopping_bag_outlined,
                      label: s.cart,
                      selected: active == NavTab.cart,
                      brand: brand,
                      badge: active == NavTab.cart ? 0 : count,
                      onTap: () => go(NavTab.cart),
                    ),
                  ),
                  _Item(
                    icon: Icons.confirmation_number_outlined,
                    label: s.myOrders,
                    selected: active == NavTab.orders,
                    brand: brand,
                    onTap: () => go(NavTab.orders),
                  ),
                  _Item(
                    icon: Icons.person_outline_rounded,
                    label: s.myAccount,
                    selected: active == NavTab.account,
                    brand: brand,
                    onTap: () => go(NavTab.account),
                  ),
                ],
              ),
            ),
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
    required this.brand,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color brand;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final pill = AnimatedContainer(
      duration: AppMotion.dur(context, AppMotion.slow),
      curve: AppMotion.curve,
      width: selected ? 112 : 52,
      height: 52,
      decoration: BoxDecoration(
        color: selected ? brand : Ds.surface,
        borderRadius: BorderRadius.circular(99),
      ),
      child: selected
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: Colors.white),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
                ),
              ],
            )
          : Icon(icon, size: 22, color: Ds.ink2),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          pill,
          if (badge > 0)
            PositionedDirectional(
              top: 6,
              end: 8,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brand,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Ds.surface, width: 2),
                ),
                child: Text('$badge',
                    style: const TextStyle(
                        fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
              ),
            ),
        ],
      ),
    );
  }
}
