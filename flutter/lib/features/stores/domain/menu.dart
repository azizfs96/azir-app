/// ============================================================================
/// THE RESTAURANT MENU, AS THE APP CONSUMES IT (RestaurantEngine)
///
/// Mirrors the storefront payload's `menu` key: categories → items → option
/// groups → options. Only what a customer browsing and ordering needs — the
/// merchant-only flags (is_active) never leave the server.
///
/// Option PRICING is a delta on the item's base price, and the total is only
/// ever computed here for DISPLAY. The authoritative price is recomputed
/// server-side at order time (R3) — the client is never trusted with money.
/// ============================================================================
library;

class MenuOption {
  const MenuOption({
    required this.id,
    required this.name,
    required this.priceDelta,
    this.isAvailable = true,
  });

  factory MenuOption.fromJson(Map<String, dynamic> json) => MenuOption(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        priceDelta: (json['price_delta'] as num?)?.toDouble() ?? 0,
        isAvailable: json['is_available'] as bool? ?? true,
      );

  final int id;
  final String name;
  final double priceDelta;
  final bool isAvailable;
}

class MenuOptionGroup {
  const MenuOptionGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.options,
  });

  factory MenuOptionGroup.fromJson(Map<String, dynamic> json) => MenuOptionGroup(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        minSelect: json['min_select'] as int? ?? 0,
        maxSelect: json['max_select'] as int? ?? 1,
        options: ((json['options'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MenuOption.fromJson)
            .toList(),
      );

  final int id;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<MenuOption> options;

  bool get isRequired => minSelect > 0;

  /// A single-choice group (size) renders as radios; multi (extras) as checks.
  bool get isSingleChoice => maxSelect == 1;
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.image,
    this.calories,
    this.categoryId,
    this.isAvailable = true,
    this.isFeatured = false,
    this.optionGroups = const [],
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        description: json['description'] as String?,
        image: json['image'] as String?,
        calories: json['calories'] as int?,
        categoryId: json['category_id'] as int?,
        isAvailable: json['is_available'] as bool? ?? true,
        isFeatured: json['is_featured'] as bool? ?? false,
        optionGroups: ((json['option_groups'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MenuOptionGroup.fromJson)
            .toList(),
      );

  final int id;
  final String name;
  final double price;
  final String? description;
  final String? image;
  final int? calories;
  final int? categoryId;
  final bool isAvailable;
  final bool isFeatured;
  final List<MenuOptionGroup> optionGroups;
}

class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    required this.items,
    this.image,
  });

  factory MenuCategory.fromJson(Map<String, dynamic> json) => MenuCategory(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        image: json['image'] as String?,
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MenuItem.fromJson)
            .toList(),
      );

  final int id;
  final String name;
  final String? image;
  final List<MenuItem> items;
}

/// The whole menu tree for one restaurant storefront.
class Menu {
  const Menu({required this.categories, required this.uncategorised});

  factory Menu.fromJson(Map<String, dynamic> json) => Menu(
        categories: ((json['categories'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MenuCategory.fromJson)
            .toList(),
        uncategorised: ((json['uncategorised'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MenuItem.fromJson)
            .toList(),
      );

  final List<MenuCategory> categories;
  final List<MenuItem> uncategorised;

  /// Every orderable dish flattened — used for the "الأكثر طلباً" strip.
  List<MenuItem> get allItems => [
        ...categories.expand((c) => c.items),
        ...uncategorised,
      ];

  List<MenuItem> get featured => allItems.where((i) => i.isFeatured).toList();

  bool get isEmpty => allItems.isEmpty;
}
