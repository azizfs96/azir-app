import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/haptics.dart';
import '../../core/localization/strings.dart';
import '../menu/cart_controller.dart';
import '../stores/data/store_repository.dart';
import '../stores/domain/menu.dart';
import 'grocery_nav_bar.dart';
import 'grocery_product_card.dart';
import 'grocery_theme.dart';
import 'grocery_widgets.dart';

/// /s/:token/search for a supermarket — Figma "Supermarket – Search": the
/// focused field (dark-green ring) beside a back circle, recent searches as
/// chips, the "most requested" list with rank badges, and suggested compact
/// cards. Typing replaces the sections with a 3-column grid of matches.
class GrocerySearchScreen extends ConsumerStatefulWidget {
  const GrocerySearchScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<GrocerySearchScreen> createState() => _GrocerySearchScreenState();
}

class _GrocerySearchScreenState extends ConsumerState<GrocerySearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  List<String> _recent = const [];

  String get _recentKey => 'wasla.grocery_recent.${widget.token}';

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() => _recent = prefs.getStringList(_recentKey) ?? const []);
    } catch (_) {}
  }

  Future<void> _saveRecent(List<String> list) async {
    setState(() => _recent = list);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, list);
    } catch (_) {}
  }

  void _remember(String term) {
    final t = term.trim();
    if (t.isEmpty) return;
    _saveRecent([t, ..._recent.where((r) => r != t)].take(6).toList());
  }

  void _search(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    setState(() => _query = term);
    _remember(term);
  }

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final store = ref.watch(storefrontProvider(widget.token)).value;
    final menu = store?.menu ?? const Menu(categories: [], uncategorised: []);
    final glyphOf = glyphByItem(menu);
    final cart = ref.watch(cartForStoreProvider(widget.token));
    final featured = menu.featured.where((i) => i.isAvailable).toList();
    final popular = (featured.isNotEmpty ? featured : menu.allItems).take(5).toList();
    final suggested = (featured.length >= 3 ? featured : menu.allItems).take(3).toList();

    final q = _query.trim();
    final results = q.isEmpty
        ? const <MenuItem>[]
        : menu.allItems.where((i) => i.name.contains(q) || (i.description ?? '').contains(q)).toList();

    final width = MediaQuery.sizeOf(context).width;
    final cellW = (width - Gr.pageX * 2 - 10 * 2) / 3;
    final cellH = GroceryProductCard.heightFor(cellW, GroceryCardStyle.compact);

    SliverGrid grid(List<MenuItem> items) => SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 20,
            mainAxisExtent: cellH,
          ),
          delegate: SliverChildBuilderDelegate(
            (_, i) => GroceryProductCard(
              token: widget.token,
              item: items[i],
              s: s,
              style: GroceryCardStyle.compact,
              fallbackGlyph: glyphOf[items[i].id] ?? '🛒',
            ),
            childCount: items.length,
          ),
        );

    Widget header(String title, {VoidCallback? onAction, String? action}) => Row(
          children: [
            Expanded(child: Text(title, style: Gr.text(18, weight: 800, height: 1.25))),
            if (action != null)
              GestureDetector(
                onTap: onAction,
                behavior: HitTestBehavior.opaque,
                child: Text(action, style: Gr.text(13, weight: 600, color: Gr.ink3)),
              ),
          ],
        );

    return Scaffold(
      backgroundColor: Gr.bg,
      body: Stack(
        children: [
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(Gr.pageX, MediaQuery.paddingOf(context).top + 4, Gr.pageX, 0),
                sliver: SliverList.list(children: [
                  Row(
                    children: [
                      GrCircleButton(
                        icon: 'back',
                        flipForRtl: true,
                        onTap: () => context.canPop() ? context.pop() : context.go('/s/${widget.token}'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _SearchField(controller: _controller, hint: s.grocerySearchFieldHint, onChanged: (v) => setState(() => _query = v), onSubmitted: _remember)),
                    ],
                  ),
                  const SizedBox(height: 22),
                ]),
              ),
              if (q.isNotEmpty) ...[
                if (results.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(child: Text(s.noResults, style: Gr.text(14, color: Gr.ink3))),
                    ),
                  )
                else
                  SliverPadding(padding: const EdgeInsets.symmetric(horizontal: Gr.pageX), sliver: grid(results)),
              ] else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: Gr.pageX),
                  sliver: SliverList.list(children: [
                    if (_recent.isNotEmpty) ...[
                      header(s.groceryRecentSearches, action: s.clearAll, onAction: () => _saveRecent(const [])),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 12,
                        children: [
                          for (final r in _recent)
                            GrChip(
                              label: r,
                              onTap: () => _search(r),
                              leading: const GrIcon('clock', size: 12),
                              trailing: GestureDetector(
                                onTap: () => _saveRecent(_recent.where((x) => x != r).toList()),
                                child: const GrIcon('close', size: 14),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (popular.isNotEmpty) ...[
                      header(s.groceryMostRequested),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Gr.surface,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: Gr.shadow(6, 18, 0.05),
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < popular.length; i++)
                              _PopularRow(
                                rank: i + 1,
                                item: popular[i],
                                last: i == popular.length - 1,
                                s: s,
                                onTap: () => _search(popular[i].name),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (suggested.isNotEmpty) ...[
                      header(s.grocerySuggested, action: s.seeAll, onAction: () => context.push('/s/${widget.token}/category/featured')),
                      const SizedBox(height: 12),
                    ],
                  ]),
                ),
              if (q.isEmpty && suggested.isNotEmpty)
                SliverPadding(padding: const EdgeInsets.symmetric(horizontal: Gr.pageX), sliver: grid(suggested)),
              SliverToBoxAdapter(
                child: SizedBox(height: groceryBottomClearance(context, hasCart: !cart.isEmpty, withTabBar: false)),
              ),
            ],
          ),
          if (!cart.isEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: GroceryNavBar.bottomInset(context)),
                child: GroceryCartBar(token: widget.token),
              ),
            ),
        ],
      ),
    );
  }
}

/// Figma "Search Field (focused)": a white 52pt pill with a 1.5pt dark-green
/// border and a soft 4pt ring, the search glyph at the start and a clear
/// button at the end once there is text.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hint, required this.onChanged, required this.onSubmitted});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsetsDirectional.only(start: 16, end: 6),
      decoration: BoxDecoration(
        color: Gr.surface,
        borderRadius: BorderRadius.circular(Gr.pill),
        border: Border.all(color: Gr.primary, width: 1.5),
        boxShadow: [BoxShadow(color: Gr.primary.withValues(alpha: 0.12), spreadRadius: 4)],
      ),
      child: Row(
        children: [
          const GrIcon('search_dark', size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              cursorColor: Gr.primary,
              style: Gr.text(14, height: 1.25),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: Gr.text(14, color: Gr.ink3, height: 1.25),
                // The pill itself is the field; no Material border in any state.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => value.text.isEmpty
                ? const SizedBox(width: 40)
                : GestureDetector(
                    onTap: () {
                      AppHaptics.tick();
                      controller.clear();
                      onChanged('');
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(color: Gr.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Figma "Trending List" row: a rank badge (lime for the top three), the name,
/// and the price at the far end. Divided by a hairline except the last.
class _PopularRow extends StatelessWidget {
  const _PopularRow({required this.rank, required this.item, required this.last, required this.s, required this.onTap});

  final int rank;
  final MenuItem item;
  final bool last;
  final Strings s;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: Gr.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: rank <= 3 ? Gr.lime : Gr.surface2, shape: BoxShape.circle),
              child: Text('$rank', style: Gr.text(12, weight: 800, color: Gr.primary, height: 1.25)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Gr.text(14, weight: 600, height: 1.25))),
            Text(Gr.price(item.price, s.sar), style: Gr.text(11, weight: 700, color: Gr.primary, height: 1.25)),
            const SizedBox(width: 4),
            const GrIcon('trend', size: 14),
          ],
        ),
      ),
    );
  }
}
