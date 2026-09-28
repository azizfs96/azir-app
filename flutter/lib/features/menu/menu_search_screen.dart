import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/strings.dart';
import '../../core/theme/app_theme.dart';
import '../stores/data/store_repository.dart';
import '../stores/domain/menu.dart';
import '../stores/presentation/store_avatar.dart';
import 'menu_view.dart';

/// Search within one store's menu (Jahez's search): a field at the top and the
/// matching dishes as the same grid cards used everywhere else.
class MenuSearchScreen extends ConsumerStatefulWidget {
  const MenuSearchScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<MenuSearchScreen> createState() => _MenuSearchScreenState();
}

class _MenuSearchScreenState extends ConsumerState<MenuSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<MenuItem> _allItems(Menu menu) => [
        for (final c in menu.categories) ...c.items,
        ...menu.uncategorised,
      ];

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final store = ref.watch(storefrontProvider(widget.token)).value;
    final brand = store != null ? brandColorOf(store.brandColor) : AppColors.ink900;
    final menu = store?.menu ?? const Menu(categories: [], uncategorised: []);

    final q = _query.trim();
    final results = q.isEmpty
        ? <MenuItem>[]
        : _allItems(menu)
            .where((i) => i.name.contains(q) || (i.description ?? '').contains(q))
            .toList();

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.cream,
        surfaceTintColor: Colors.transparent,
        title: SizedBox(
          height: 42,
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: s.searchMenu,
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.ink400),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
      body: q.isEmpty
          ? const SizedBox.shrink()
          : results.isEmpty
              ? Center(child: Text(s.noResults, style: const TextStyle(color: AppColors.ink500)))
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: results.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.68,
                  ),
                  itemBuilder: (_, i) => DishCard(
                    item: results[i],
                    storeToken: widget.token,
                    brand: brand,
                    s: s,
                    prepMinutes: store?.configuration.defaultPrepMinutes ?? 0,
                  ),
                ),
    );
  }
}
