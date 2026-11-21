/// A real-looking glyph for a grocery category that has no photo yet.
///
/// Merchants upload a category image from the dashboard; until they do, the
/// category name picks a food emoji (Apple's full-colour artwork on iOS) so
/// the round chips read like the design reference instead of a generic leaf.
/// Keyword matching is deliberately broad and bilingual.
String categoryGlyph(String name) {
  final n = name.toLowerCase();
  bool has(List<String> words) => words.any(n.contains);

  if (has(['خضار', 'خضر', 'فواكه', 'فاكهة', 'fruit', 'veget', 'produce'])) return '🍅';
  if (has(['ألبان', 'البان', 'حليب', 'بيض', 'جبن', 'dairy', 'egg', 'milk', 'cheese'])) return '🥛';
  if (has(['مخبوز', 'خبز', 'معجنات', 'bakery', 'bread', 'pastr'])) return '🥐';
  if (has(['سناك', 'شيبس', 'مقرمشات', 'بسكويت', 'snack', 'chips', 'crisps', 'biscuit'])) return '🍿';
  if (has(['مشروب', 'عصير', 'ماء', 'مياه', 'غازي', 'drink', 'beverage', 'juice', 'water', 'soda'])) return '🧃';
  if (has(['منظف', 'منزل', 'تنظيف', 'household', 'clean', 'home'])) return '🧴';
  if (has(['لحوم', 'لحم', 'دجاج', 'meat', 'chicken', 'poultry', 'butcher'])) return '🍗';
  if (has(['سمك', 'أسماك', 'بحرية', 'fish', 'seafood'])) return '🐟';
  if (has(['مجمد', 'ثلج', 'frozen', 'ice'])) return '🧊';
  if (has(['حلويات', 'حلوى', 'شوكولا', 'sweet', 'candy', 'chocolate', 'dessert'])) return '🍫';
  if (has(['قهوة', 'شاي', 'coffee', 'tea'])) return '☕';
  if (has(['أطفال', 'اطفال', 'رضع', 'baby', 'kids'])) return '🍼';
  if (has(['عناية', 'شامبو', 'صابون', 'care', 'beauty', 'shampoo', 'soap'])) return '🧼';
  if (has(['أرز', 'ارز', 'معكرونة', 'بقوليات', 'معلبات', 'بقالة', 'rice', 'pasta', 'pantry', 'grocery', 'canned'])) return '🍚';
  if (has(['توابل', 'بهارات', 'spice', 'season'])) return '🧂';
  if (has(['مكسرات', 'تمور', 'nuts', 'dates'])) return '🥜';
  if (has(['حيوانات', 'pet'])) return '🐾';
  return '🛒';
}
