import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/bump.dart';
import '../menu/cart_controller.dart';
import 'grocery_theme.dart';

/// The supermarket's bottom nav: Home · Categories · Cart · Orders · Account —
/// a frosted white bar with the active tab lit in the accent colour. Five
/// equal columns, 24pt icons, 4pt to the label; the iOS home indicator is
/// handled by [SafeArea].
enum GroceryTab { home, categories, cart, orders, account }

class GroceryNavBar extends ConsumerWidget {
  const GroceryNavBar({super.key, required this.token, required this.active});

  final String token;
  final GroceryTab active;

  /// Bar height above the bottom safe area; screens pad their content by this
  /// so the bar never covers the last row.
  static const height = 64.0;

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
      (GroceryTab.home, Icons.home_rounded, s.homeTab),
      (GroceryTab.categories, Icons.grid_view_rounded, s.categoriesTab),
      (GroceryTab.cart, Icons.shopping_cart_outlined, s.cart),
      (GroceryTab.orders, Icons.receipt_long_outlined, s.myOrders),
      (GroceryTab.account, Icons.person_outline_rounded, s.myAccount),
    ];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(Gr.s24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Gr.surface.withValues(alpha: 0.86),
            border: const Border(top: BorderSide(color: Gr.line)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  for (final (tab, icon, label) in items)
                    Expanded(
                      child: _Item(
                        icon: icon,
                        label: label,
                        selected: tab == active,
                        badge: tab == GroceryTab.cart && active != GroceryTab.cart ? count : 0,
                        onTap: () => go(tab),
                      ),
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
  const _Item({required this.icon, required this.label, required this.selected, required this.onTap, this.badge = 0});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Gr.accent : Gr.ink3;
    final iconWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 24, color: color),
        if (badge > 0)
          PositionedDirectional(
            top: -Gr.s4,
            end: -Gr.s8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16),
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: Gr.s4),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Gr.accent, borderRadius: BorderRadius.circular(99)),
              child: Text('$badge',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Gr.onAccent, height: 1)),
            ),
          ),
      ],
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Bump(value: badge, child: iconWidget),
          const SizedBox(height: Gr.s4),
          AnimatedDefaultTextStyle(
            duration: AppMotion.dur(context, AppMotion.fast),
            style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
