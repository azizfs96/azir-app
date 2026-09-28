import 'package:flutter/material.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/riyal_price.dart';
import '../stores/domain/menu.dart';
import '../stores/presentation/store_avatar.dart';
import 'item_sheet.dart';

/// ============================================================================
/// THE MENU (RestaurantEngine, R2) — modelled on Jahez/HungerStation.
///
///   الأكثر مبيعاً                              ← best-sellers, ALWAYS a
///   ┌───────┐ ┌───────┐                          2-column grid of image cards
///   │ photo │ │ photo │
///   │  + ▸  │ │  + ▸  │
///   │ اسم   │ │ اسم   │
///   │ ٢٧ ﷼ │ │ ١١﷼  │
///   └───────┘ └───────┘
///   ────────────────────────
///   أصناف القائمة              [ ≣  �damaged? ]  ← section heading + view toggle
///                                                 (default = large)
///   منيو الطيبين                               ← category name (ONCE, here)
///   ┌──────────────────────┐
///   │        photo         │                    ← large single-column card:
///   │  +                   │                      image, +, name, price,
///   └──────────────────────┘                      calories · description
///   صامولي الطيبين   ١٤.٧٥ ﷼
///   ٤٠٠ سعرة · شاورما الدجاج…
///
/// No category CHIPS: the name appears once, as its section header — showing
/// it as both a chip and a header was the duplication the merchant flagged.
/// The toggle flips the CATEGORY items between large (default) and a compact
/// 2-column grid; best-sellers stay a grid either way.
/// ============================================================================
class MenuView extends StatefulWidget {
  const MenuView({
    super.key,
    required this.storeToken,
    required this.menu,
    required this.brand,
    required this.s,
    this.prepMinutes = 0,
  });

  final String storeToken;
  final Menu menu;
  final Color brand;
  final Strings s;

  /// The kitchen's default prep time, shown on every dish card (Jahez-style).
  final int prepMinutes;

  @override
  State<MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<MenuView> {
  /// Category items default to the LARGE single-column card (Jahez's default);
  /// the toggle switches to a compact 2-column grid.
  bool _large = false;

  /// The chip the customer last tapped, highlighted like Jahez's active pill.
  int _activeChip = 0;

  /// One anchor per section so a chip can scroll it to the top of the
  /// storefront's scroll view.
  final Map<String, GlobalKey> _anchors = {};
  GlobalKey _anchorFor(String id) => _anchors.putIfAbsent(id, GlobalKey.new);

  void _jumpTo(int index, String id) {
    setState(() => _activeChip = index);
    final ctx = _anchors[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final menu = widget.menu;

    if (menu.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
          child: Column(
            children: [
              const Icon(Icons.restaurant_menu_rounded, size: 40, color: AppColors.ink300),
              const SizedBox(height: 14),
              Text(s.menuEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink900)),
              const SizedBox(height: 6),
              Text(s.menuEmptyHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.ink500)),
            ],
          ),
        ),
      );
    }

    final featured = menu.featured;

    // Every scrollable section, in order, each with a stable id shared by its
    // chip and its scroll anchor. Best-sellers first, then categories.
    final sections = <({String id, String title, String? image, List<MenuItem> items, bool featured})>[
      if (featured.isNotEmpty)
        (id: 'featured', title: s.featuredSection, image: null, items: featured, featured: true),
      for (final c in menu.categories)
        if (c.items.isNotEmpty)
          (id: 'cat-${c.id}', title: c.name, image: c.image, items: c.items, featured: false),
      if (menu.uncategorised.isNotEmpty)
        (id: 'uncat', title: s.menuTab, image: null, items: menu.uncategorised, featured: false),
    ];

    // The filter row (view toggle + category chips) is PINNED to the top of the
    // scroll view, so it stays reachable while the customer scrolls the menu.
    // The sections scroll underneath it.
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _FilterBarDelegate(
            height: 60,
            child: Container(
              color: AppColors.cream,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  _ViewToggle(large: _large, onChanged: (v) => setState(() => _large = v)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CategoryChips(
                      sections: [for (final sec in sections) (title: sec.title, featured: sec.featured)],
                      active: _activeChip.clamp(0, sections.length - 1),
                      onTap: (i) => _jumpTo(i, sections[i].id),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              // ---- the sections, each anchored + headed ---------------------
              for (final section in sections) ...[
                Padding(
                  key: _anchorFor(section.id),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Text(section.title,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                ),
                // Best-sellers is always a grid; categories follow the toggle.
                if (section.featured || !_large)
                  _Grid(
                      items: section.items,
                      storeToken: widget.storeToken,
                      brand: widget.brand,
                      s: s,
                      prepMinutes: widget.prepMinutes)
                else
                  for (final item in section.items)
                    _LargeCard(
                        item: item,
                        storeToken: widget.storeToken,
                        brand: widget.brand,
                        s: s,
                        prepMinutes: widget.prepMinutes),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Pins the menu's filter bar to the top of the scroll view. Fixed height, an
/// opaque cream background so the dishes scroll cleanly behind it.
class _FilterBarDelegate extends SliverPersistentHeaderDelegate {
  _FilterBarDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;

  @override
  bool shouldRebuild(_FilterBarDelegate old) => old.child != child || old.height != height;
}

/// Flip between large single-column cards and a compact 2-column grid.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.large, required this.onChanged});

  final bool large;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, bool isLarge) => GestureDetector(
          onTap: () => onChanged(isLarge),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: large == isLarge ? AppColors.ink900 : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon,
                size: 18, color: large == isLarge ? Colors.white : AppColors.ink400),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.ink100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Large single-card view (default) — the filled-rectangle icon.
          btn(Icons.crop_16_9_rounded, true),
          const SizedBox(width: 2),
          // Compact grid — the list-lines icon.
          btn(Icons.grid_view_rounded, false),
        ],
      ),
    );
  }
}

/// The horizontal category pills (Jahez's top bar). Tapping one jumps to its
/// section; the active one is painted like the reference's black pill.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.sections, required this.active, required this.onTap});

  final List<({String title, bool featured})> sections;
  final int active;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final section = sections[i];
          final isActive = i == active;
          return GestureDetector(
            onTap: () => onTap(i),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isActive ? AppColors.ink900 : AppColors.ink100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(section.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isActive ? Colors.white : AppColors.ink700,
                  )),
            ),
          );
        },
      ),
    );
  }
}

void _open(BuildContext context, String token, MenuItem item, Color brand) {
  if (!item.isAvailable) return;
  showItemSheet(context, storeToken: token, item: item, brand: brand);
}

/// A small round "+" affordance overlaid on a dish image — opens the sheet.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Jahez-style: a solid dark square with a white "+", not a white chip.
    return Material(
      color: AppColors.ink900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.all(7),
          child: Icon(Icons.add_rounded, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

class _SoldOutBadge extends StatelessWidget {
  const _SoldOutBadge({required this.s});
  final Strings s;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.bad, borderRadius: BorderRadius.circular(8)),
        child: Text(s.soldOut,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
      );
}

Widget _dishImage(String? path, {BoxFit fit = BoxFit.cover}) {
  final url = logoUrlOf(path);
  return url != null
      ? Image.network(url, fit: fit,
          errorBuilder: (_, _, _) =>
              const Center(child: Icon(Icons.restaurant_rounded, size: 30, color: AppColors.ink300)))
      : const Center(child: Icon(Icons.restaurant_rounded, size: 30, color: AppColors.ink300));
}

/// The 2-column grid of dish cards — the Jahez reference exactly: a white card
/// with the name and price centred at the top, the dish image in the middle,
/// and a bottom row carrying the "+" button beside the calories and prep time.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.items,
    required this.storeToken,
    required this.brand,
    required this.s,
    required this.prepMinutes,
  });

  final List<MenuItem> items;
  final String storeToken;
  final Color brand;
  final Strings s;
  final int prepMinutes;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 16,
        childAspectRatio: 0.68,
      ),
      itemBuilder: (_, i) => DishCard(
        item: items[i],
        storeToken: storeToken,
        brand: brand,
        s: s,
        prepMinutes: prepMinutes,
      ),
    );
  }
}

/// One Jahez-style dish card.
class DishCard extends StatelessWidget {
  const DishCard({
    super.key,
    required this.item,
    required this.storeToken,
    required this.brand,
    required this.s,
    required this.prepMinutes,
  });

  final MenuItem item;
  final String storeToken;
  final Color brand;
  final Strings s;
  final int prepMinutes;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context, storeToken, item, brand),
      child: Opacity(
        opacity: item.isAvailable ? 1 : 0.55,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            children: [
              Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink900)),
              const SizedBox(height: 4),
              RiyalPrice(amount: item.price, size: 15),
              const SizedBox(height: 6),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _dishImage(item.image, fit: BoxFit.contain)),
                    if (!item.isAvailable)
                      PositionedDirectional(top: 0, end: 0, child: _SoldOutBadge(s: s)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Metrics on the start (right in RTL); "+" on the end (left) —
                  // exactly the reference's layout.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.calories != null)
                        _MetaRow(
                          icon: Icons.local_fire_department_rounded,
                          iconColor: AppColors.flame,
                          text: s.caloriesLabel(item.calories!),
                        ),
                      if (prepMinutes > 0) ...[
                        const SizedBox(height: 3),
                        _MetaRow(
                          icon: Icons.access_time_rounded,
                          iconColor: AppColors.ink400,
                          text: s.minShort(prepMinutes),
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  if (item.isAvailable)
                    _AddButton(onTap: () => _open(context, storeToken, item, brand)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tiny "value + icon" metric (calories, prep time) as the reference shows it.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.iconColor, required this.text});

  final IconData icon;
  final Color iconColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink500)),
        const SizedBox(width: 3),
        Icon(icon, size: 14, color: iconColor),
      ],
    );
  }
}

/// The large single-column card — image on top, then name, price, and
/// (uniquely to this view) calories + description, mirroring the reference.
/// The list-view row (Jahez's list toggle): a horizontal white card with the
/// text on one side and a thumbnail (with its "+") on the other.
class _LargeCard extends StatelessWidget {
  const _LargeCard({
    required this.item,
    required this.storeToken,
    required this.brand,
    required this.s,
    required this.prepMinutes,
  });

  final MenuItem item;
  final String storeToken;
  final Color brand;
  final Strings s;
  final int prepMinutes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: GestureDetector(
        onTap: () => _open(context, storeToken, item, brand),
        child: Opacity(
          opacity: item.isAvailable ? 1 : 0.55,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 6)),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink900)),
                      if ((item.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(item.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, height: 1.3, color: AppColors.ink500)),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (item.calories != null) ...[
                            _MetaRow(
                              icon: Icons.local_fire_department_rounded,
                              iconColor: AppColors.flame,
                              text: s.caloriesLabel(item.calories!),
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (prepMinutes > 0)
                            _MetaRow(
                              icon: Icons.access_time_rounded,
                              iconColor: AppColors.ink400,
                              text: s.minShort(prepMinutes),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      RiyalPrice(amount: item.price, size: 16),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 104,
                  height: 104,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ColoredBox(color: AppColors.cream, child: _dishImage(item.image)),
                        ),
                      ),
                      PositionedDirectional(
                        start: 6,
                        bottom: 6,
                        child: item.isAvailable
                            ? _AddButton(onTap: () => _open(context, storeToken, item, brand))
                            : const SizedBox.shrink(),
                      ),
                      if (!item.isAvailable)
                        PositionedDirectional(top: 6, end: 6, child: _SoldOutBadge(s: s)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
