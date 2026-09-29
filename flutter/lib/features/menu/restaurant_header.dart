import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/open_badge.dart';
import '../stores/domain/storefront.dart';
import '../stores/presentation/store_avatar.dart';
import 'fulfillment.dart';

/// ============================================================================
/// THE RESTAURANT STOREFRONT HEADER — the Jahez home layout.
///
/// Store identity, then the fulfilment pills (delivery / curbside / pickup /
/// dine-in — only the ones the merchant enabled), the pickup branch row, and a
/// promotional banner. The chosen fulfilment mode is shared with the cart via
/// fulfillmentModeProvider so the two never disagree.
/// ============================================================================
class RestaurantHeader extends ConsumerWidget {
  const RestaurantHeader({
    super.key,
    required this.store,
    required this.s,
    required this.brand,
    required this.onOrderNow,
  });

  final Storefront store;
  final Strings s;
  final Color brand;
  final VoidCallback onOrderNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = enabledModes(store.configuration);

    // Choose a default mode once, after the first frame, without rebuilding now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(fulfillmentModeProvider.notifier).ensureDefault(store.token, modes);
    });
    final selected = ref.watch(modeForStoreProvider(store.token)) ??
        (modes.isNotEmpty ? modes.first : null);

    return Container(
      color: AppColors.cream,
      // The identity + action icons live in the pinned RestaurantTopBar above,
      // so this scrolling section starts straight at the fulfilment pills.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- fulfilment pills -------------------------------------------
          if (modes.length > 1)
            SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: modes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _Pill(
                  mode: modes[i],
                  selected: modes[i] == selected,
                  s: s,
                  onTap: () =>
                      ref.read(fulfillmentModeProvider.notifier).set(store.token, modes[i]),
                ),
              ),
            ),

          if (modes.length > 1) const SizedBox(height: 14),

          // ---- pickup branch row ------------------------------------------
          if (store.branches.isNotEmpty) _BranchRow(store: store, s: s),

          const SizedBox(height: 16),

          // ---- promotional banner -----------------------------------------
          _Banner(store: store, brand: brand, onTap: onOrderNow),
        ],
      ),
    );
  }
}

/// The pinned top bar (Jahez-style): back · store name · search/share. Stays at
/// the top of the scroll view — below the notch — while the menu scrolls under
/// it, so the category chips pin cleanly beneath it instead of hitting the
/// status bar.
class RestaurantTopBar extends StatelessWidget {
  const RestaurantTopBar({
    super.key,
    required this.store,
    required this.onSearch,
    required this.onShare,
    this.onBack,
  });

  final Storefront store;
  final VoidCallback onSearch;
  final VoidCallback onShare;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: AppColors.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      leadingWidth: 64,
      leading: onBack != null
          ? Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Center(child: _CircleIcon(icon: Icons.arrow_back_rounded, onTap: onBack!)),
            )
          : null,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(store.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink900)),
          ),
          if (store.isVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified_rounded, size: 17, color: AppColors.ink900),
          ],
          if (store.isOpen != null) ...[
            const SizedBox(width: 8),
            OpenBadge(open: store.isOpen!, s: Strings.of(context), compact: true),
          ],
        ],
      ),
      actions: [
        _CircleIcon(icon: Icons.search_rounded, onTap: onSearch),
        const SizedBox(width: 8),
        _CircleIcon(icon: Icons.ios_share_rounded, onTap: onShare),
        const SizedBox(width: 12),
      ],
    );
  }
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Icon(icon, size: 20, color: AppColors.ink900),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.mode, required this.selected, required this.s, required this.onTap});

  final FulfillmentMode mode;
  final bool selected;
  final Strings s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7E2D9) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? Colors.transparent : const Color(0x14000000)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(mode.icon, size: 19, color: AppColors.ink900),
            const SizedBox(width: 8),
            Text(mode.label(s),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: AppColors.ink900)),
          ],
        ),
      ),
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({required this.store, required this.s});
  final Storefront store;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    final branch = store.branches.first;
    // RTL: store icon on the start (right), chevron on the end (left).
    return Row(
      children: [
        const Icon(Icons.storefront_rounded, size: 22, color: AppColors.ink900),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.pickupBranch,
                style: const TextStyle(fontSize: 12.5, color: AppColors.ink500)),
            const SizedBox(height: 2),
            Text(branch.name,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink900)),
          ],
        ),
        const Spacer(),
        const Icon(Icons.keyboard_arrow_down_rounded, size: 24, color: AppColors.ink400),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.store, required this.brand, required this.onTap});
  final Storefront store;
  final Color brand;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = logoUrlOf(store.cover);
    // The merchant's own banner image, shown clean — no overlaid button or mark.
    // A store without a banner keeps a branded gradient placeholder.
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 168,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [const Color(0xFF1A1512), brand.withValues(alpha: 0.85)],
            ),
          ),
          child: cover != null
              ? Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink())
              : const Center(
                  child: Icon(Icons.local_fire_department_rounded, size: 34, color: AppColors.flame)),
        ),
      ),
    );
  }
}
