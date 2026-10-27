import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_image.dart';
import '../../core/widgets/riyal_price.dart';
import '../stores/domain/menu.dart';
import '../stores/presentation/store_avatar.dart';
import 'cart_controller.dart';
import 'item_sheet.dart';

/// ============================================================================
/// THE MENU — the design system's home list.
///
///   [ الأكثر مبيعاً ] [ المحاصيل ] [ القهوة الحارة ] …   ← sticky category chips
///   الأكثر مبيعاً                                           ← big section head
///   ┌───────┐ ┌───────┐   square image tiles (hairline border, radius 20),
///   │ photo │ │ photo │   the "+" INSIDE the tile, a cart-count badge when
///   │     + │ │     + │   the dish is already in the cart; name + price
///   └───────┘ └───────┘   centred underneath — no card box, no shadow.
///     اسم        اسم
///    ﷼ ١٨       ﷼ ٩٢
///   أصناف القائمة                                   [⊞]  ← head + view toggle
///   المحاصيل                                               ← category head
///   ┌────────────────────────────────────────┐
///   │ name / desc / meta / price   [thumb +] │       ← list row (the default)
///   └────────────────────────────────────────┘
/// ============================================================================
/// One scrollable section of the menu: best-sellers first, then each category.
typedef MenuSection = ({String id, String title, List<MenuItem> items, bool featured});

/// The sections the chips navigate between — shared by the menu and the
/// storefront's sticky chip bar so both agree on titles, order and ids.
List<MenuSection> menuSections(Menu menu, Strings s) {
  final featured = menu.featured;
  return [
    if (featured.isNotEmpty)
      (id: 'featured', title: s.featuredSection, items: featured, featured: true),
    for (final c in menu.categories)
      if (c.items.isNotEmpty) (id: 'cat-${c.id}', title: c.name, items: c.items, featured: false),
    if (menu.uncategorised.isNotEmpty)
      (id: 'uncat', title: s.menuTab, items: menu.uncategorised, featured: false),
  ];
}

/// Height of the chip bar row (chips 46 + 8 padding each side).
const double kMenuChipBarHeight = 62;

class MenuView extends StatefulWidget {
  const MenuView({
    super.key,
    required this.storeToken,
    required this.menu,
    required this.brand,
    required this.s,
    this.prepMinutes = 0,
    this.chipsSlotKey,
    this.activeChip,
    this.onChipTap,
    this.anchorFor,
  });

  final String storeToken;
  final Menu menu;
  final Color brand;
  final Strings s;

  /// The kitchen's default prep time, shown on list rows that carry no calories.
  final int prepMinutes;

  /// When the storefront draws the sticky chip bar itself (so it can pin under
  /// the status bar, like the design's `position: sticky`), it owns the chip
  /// state and passes it here; the in-flow row then mirrors it and the slot key
  /// lets the storefront track where that row scrolls. Left null, MenuView
  /// manages its own chips (standalone use and tests).
  final GlobalKey? chipsSlotKey;
  final int? activeChip;
  final void Function(int index, String sectionId)? onChipTap;
  final GlobalKey Function(String sectionId)? anchorFor;

  @override
  State<MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<MenuView> {
  /// Categories default to the LIST row (the design's default); the toggle
  /// switches them to the 2-column grid. Best-sellers are always a grid.
  bool _list = true;

  /// The chip the customer last tapped (only when self-managed).
  int _activeChip = 0;

  /// One anchor per section so a chip can scroll it to the top.
  final Map<String, GlobalKey> _anchors = {};
  GlobalKey _anchorFor(String id) =>
      widget.anchorFor?.call(id) ?? _anchors.putIfAbsent(id, GlobalKey.new);

  void _jumpTo(int index, String id) {
    if (widget.onChipTap != null) {
      widget.onChipTap!(index, id);
      return;
    }
    setState(() => _activeChip = index);
    jumpToMenuSection(_anchors[id]);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final menu = widget.menu;
    final brand = widget.brand;

    if (menu.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
          child: Column(
            children: [
              const Icon(Icons.restaurant_menu_rounded, size: 40, color: Ds.ink3),
              const SizedBox(height: 14),
              Text(s.menuEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Ds.ink)),
              const SizedBox(height: 6),
              Text(s.menuEmptyHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: Ds.ink2)),
            ],
          ),
        ),
      );
    }

    final sections = menuSections(menu, s);
    final firstCategory = sections.indexWhere((x) => !x.featured);
    final active = (widget.activeChip ?? _activeChip).clamp(0, sections.length - 1);

    return SliverMainAxisGroup(
      slivers: [
        // The chip row in its natural place (`.menu-bar`). The storefront draws a
        // sticky copy over it that pins under the status bar once this scrolls
        // away — which is why the row carries the storefront's slot key.
        SliverToBoxAdapter(
          child: MenuChipBar(
            key: widget.chipsSlotKey,
            titles: [for (final sec in sections) sec.title],
            active: active,
            brand: brand,
            onTap: (i) => _jumpTo(i, sections[i].id),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                // "أصناف القائمة" + the view toggle sit once, above the first category.
                if (i == firstCategory)
                  _MenuHead(
                    s: s,
                    list: _list,
                    onToggle: () {
                      AppHaptics.tick();
                      setState(() => _list = !_list);
                    },
                  ),
                _SectionHead(
                  key: _anchorFor(sections[i].id),
                  title: sections[i].title,
                  big: sections[i].featured,
                  tight: i == firstCategory,
                ),
                if (sections[i].featured || !_list)
                  _GridRows(
                    items: sections[i].items,
                    storeToken: widget.storeToken,
                    brand: brand,
                    s: s,
                    prepMinutes: widget.prepMinutes,
                  )
                else
                  for (final item in sections[i].items)
                    _ListRow(
                      item: item,
                      storeToken: widget.storeToken,
                      brand: brand,
                      s: s,
                      prepMinutes: widget.prepMinutes,
                    ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Scroll a section's anchor to the top of the storefront.
void jumpToMenuSection(GlobalKey? anchor) {
  final ctx = anchor?.currentContext;
  if (ctx != null) {
    Scrollable.ensureVisible(ctx, duration: AppMotion.slow, curve: AppMotion.curve, alignment: 0);
  }
}

/// The chip bar: the canvas background with 8pt above and below the chips.
class MenuChipBar extends StatelessWidget {
  const MenuChipBar({
    super.key,
    required this.titles,
    required this.active,
    required this.brand,
    required this.onTap,
  });

  final List<String> titles;
  final int active;
  final Color brand;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Ds.bg,
      height: kMenuChipBarHeight,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: MenuCategoryChips(titles: titles, active: active, brand: brand, onTap: onTap),
    );
  }
}

/// The horizontal category chips (`.ct`): white, hairline-bordered; the active
/// one tinted with the merchant's brand colour.
class MenuCategoryChips extends StatelessWidget {
  const MenuCategoryChips({
    super.key,
    required this.titles,
    required this.active,
    required this.brand,
    required this.onTap,
  });

  final List<String> titles;
  final int active;
  final Color brand;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: titles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final on = i == active;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: AppMotion.dur(context, AppMotion.base),
              curve: AppMotion.curve,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: on ? Ds.mix(brand, Ds.surface, 0.10) : Ds.surface,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: on ? Ds.mix(brand, Ds.line, 0.55) : Ds.line, width: 1.5),
              ),
              child: Text(titles[i],
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? Ds.ink : Ds.ink2,
                  )),
            ),
          );
        },
      ),
    );
  }
}

/// "أصناف القائمة" with the grid/list toggle (`.menu-head` + `.vtoggle`).
class _MenuHead extends StatelessWidget {
  const _MenuHead({required this.s, required this.list, required this.onToggle});

  final Strings s;
  final bool list;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(s.menuItemsHead,
              style: const TextStyle(
                  fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Ds.ink)),
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Ds.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Ds.line),
              ),
              child: Icon(list ? Icons.grid_view_rounded : Icons.view_agenda_outlined,
                  size: 21, color: Ds.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// A section heading (`.sec h2` / `.sec.big h2`). Carries the scroll anchor.
class _SectionHead extends StatelessWidget {
  const _SectionHead({super.key, required this.title, required this.big, this.tight = false});

  final String title;
  final bool big;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, big ? 24 : (tight ? 10 : 24), 20, 12),
      child: Text(title,
          style: big
              ? const TextStyle(
                  fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Ds.ink)
              : const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Ds.ink)),
    );
  }
}

void _open(BuildContext context, String token, MenuItem item, Color brand) {
  if (!item.isAvailable) return;
  showItemSheet(context, storeToken: token, item: item, brand: brand);
}

/// The brand-coloured "+" (`.plus`): 38pt rounded-12 in a tile, 28pt rounded-8
/// with a white ring when it sits on a list thumbnail's corner.
class _PlusBtn extends StatelessWidget {
  const _PlusBtn({
    required this.brand,
    required this.onTap,
    this.size = 38,
    this.radius = 12,
    this.iconSize = 18,
    this.ring = false,
  });

  final Color brand;
  final VoidCallback onTap;
  final double size;
  final double radius;
  final double iconSize;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brand,
        borderRadius: BorderRadius.circular(radius),
        border: ring ? Border.all(color: Ds.surface, width: 2) : null,
        boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 10, offset: Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            AppHaptics.tick();
            onTap();
          },
          borderRadius: BorderRadius.circular(radius),
          child: Icon(Icons.add_rounded, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }
}

/// "نفد" chip (`.soldout`).
class _SoldOutChip extends StatelessWidget {
  const _SoldOutChip({required this.s});
  final Strings s;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(color: Ds.soft, borderRadius: BorderRadius.circular(99)),
        child: Text(s.soldOut,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Ds.red)),
      );
}

/// The small brand pill (`.qb`) showing how many of this dish are in the cart.
class _CartCountBadge extends ConsumerWidget {
  const _CartCountBadge({required this.storeToken, required this.itemId, required this.brand});

  final String storeToken;
  final int itemId;
  final Color brand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartForStoreProvider(storeToken));
    final q = cart.lines.where((l) => l.item.id == itemId).fold<int>(0, (a, l) => a + l.quantity);
    if (q == 0) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brand,
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Text('$q',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
    );
  }
}

/// Sold-out dishes are shown desaturated, like the design's `filter:grayscale(1)`.
const _grayscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

Widget _dishImage(String? path, {Color placeholder = Ds.surface}) {
  return AppImage(
    url: logoUrlOf(path),
    fit: BoxFit.cover,
    placeholderColor: placeholder,
    error: const Center(child: Icon(Icons.restaurant_rounded, size: 30, color: Ds.ink3)),
  );
}

/// The 2-column grid, laid out as rows so each tile is a true square and the
/// text underneath takes its natural height (`.grid2`, gap 14).
class _GridRows extends StatelessWidget {
  const _GridRows({
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
    DishCard card(MenuItem it) =>
        DishCard(item: it, storeToken: storeToken, brand: brand, s: s, prepMinutes: prepMinutes);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: i + 2 < items.length ? 14 : 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: card(items[i])),
                  const SizedBox(width: 14),
                  Expanded(
                    child: i + 1 < items.length ? card(items[i + 1]) : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One grid dish (`.card`): a square image tile with the "+" inside, then the
/// name and the price centred beneath. No card background, no shadow.
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
    final out = !item.isAvailable;
    return GestureDetector(
      onTap: () => _open(context, storeToken, item, brand),
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: out ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ImageTile(item: item, storeToken: storeToken, brand: brand, s: s),
            const SizedBox(height: 11),
            Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Ds.ink)),
            const SizedBox(height: 3),
            Center(child: RiyalPrice(amount: item.price, size: 15.5, color: Ds.ink)),
          ],
        ),
      ),
    );
  }
}

/// The square tile (`.card .img`): white, hairline border, radius 20, the
/// image covering it, the "+" bottom-end, the cart count top-end.
class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.item, required this.storeToken, required this.brand, required this.s});

  final MenuItem item;
  final String storeToken;
  final Color brand;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    final out = !item.isAvailable;
    Widget img = _dishImage(item.image);
    if (out) img = ColorFiltered(colorFilter: _grayscale, child: img);

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: Ds.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Ds.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            img,
            if (out) PositionedDirectional(top: 10, start: 10, child: _SoldOutChip(s: s)),
            if (!out)
              PositionedDirectional(
                bottom: 10,
                end: 10,
                child: _PlusBtn(brand: brand, onTap: () => _open(context, storeToken, item, brand)),
              ),
            PositionedDirectional(
              top: 10,
              end: 10,
              child: _CartCountBadge(storeToken: storeToken, itemId: item.id, brand: brand),
            ),
          ],
        ),
      ),
    );
  }
}

/// A list row (`.lrow`): name, description, meta and price on the start; a
/// 92pt thumbnail on the end with the "+" tucked on its outer corner.
class _ListRow extends StatelessWidget {
  const _ListRow({
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
    final out = !item.isAvailable;
    final desc = item.description ?? '';
    Widget thumb = _dishImage(item.image, placeholder: Ds.soft);
    if (out) thumb = ColorFiltered(colorFilter: _grayscale, child: thumb);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GestureDetector(
        onTap: () => _open(context, storeToken, item, brand),
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: out ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(color: Ds.surface, borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Ds.ink)),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, color: Ds.ink2)),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (item.calories != null)
                            _MetaRow(
                              icon: Icons.local_fire_department_rounded,
                              iconColor: AppColors.flame,
                              text: s.caloriesLabel(item.calories!),
                            )
                          else if (prepMinutes > 0)
                            _MetaRow(
                              icon: Icons.access_time_rounded,
                              iconColor: Ds.ink3,
                              text: s.minShort(prepMinutes),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (out)
                        Text(s.soldOut,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Ds.red))
                      else
                        RiyalPrice(amount: item.price, size: 16, color: Ds.ink, weight: FontWeight.w600),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 92,
                  height: 92,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: ColoredBox(color: Ds.soft, child: thumb),
                        ),
                      ),
                      if (out) PositionedDirectional(top: 6, start: 6, child: _SoldOutChip(s: s)),
                      PositionedDirectional(
                        top: 6,
                        end: 6,
                        child: _CartCountBadge(storeToken: storeToken, itemId: item.id, brand: brand),
                      ),
                      if (!out)
                        PositionedDirectional(
                          bottom: -8,
                          end: -8,
                          child: _PlusBtn(
                            brand: brand,
                            size: 28,
                            radius: 8,
                            iconSize: 16,
                            ring: true,
                            onTap: () => _open(context, storeToken, item, brand),
                          ),
                        ),
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
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Ds.ink2)),
      ],
    );
  }
}
