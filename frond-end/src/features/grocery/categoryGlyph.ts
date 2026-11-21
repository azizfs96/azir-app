/**
 * A real-looking glyph for a grocery category without a photo — the same
 * keyword → emoji mapping the customer app uses, so the dashboard chips match
 * what the customer sees until the merchant uploads an image.
 */
const RULES: [string[], string][] = [
  [['خضار', 'خضر', 'فواكه', 'فاكهة', 'fruit', 'veget', 'produce'], '🍅'],
  [['ألبان', 'البان', 'حليب', 'بيض', 'جبن', 'dairy', 'egg', 'milk', 'cheese'], '🥛'],
  [['مخبوز', 'خبز', 'معجنات', 'bakery', 'bread', 'pastr'], '🥐'],
  [['سناك', 'شيبس', 'مقرمشات', 'بسكويت', 'snack', 'chips', 'crisps', 'biscuit'], '🍿'],
  [['مشروب', 'عصير', 'ماء', 'مياه', 'غازي', 'drink', 'beverage', 'juice', 'water', 'soda'], '🧃'],
  [['منظف', 'منزل', 'تنظيف', 'household', 'clean', 'home'], '🧴'],
  [['لحوم', 'لحم', 'دجاج', 'meat', 'chicken', 'poultry', 'butcher'], '🍗'],
  [['سمك', 'أسماك', 'بحرية', 'fish', 'seafood'], '🐟'],
  [['مجمد', 'ثلج', 'frozen', 'ice'], '🧊'],
  [['حلويات', 'حلوى', 'شوكولا', 'sweet', 'candy', 'chocolate', 'dessert'], '🍫'],
  [['قهوة', 'شاي', 'coffee', 'tea'], '☕'],
  [['أطفال', 'اطفال', 'رضع', 'baby', 'kids'], '🍼'],
  [['عناية', 'شامبو', 'صابون', 'care', 'beauty', 'shampoo', 'soap'], '🧼'],
  [['أرز', 'ارز', 'معكرونة', 'بقوليات', 'معلبات', 'بقالة', 'rice', 'pasta', 'pantry', 'grocery', 'canned'], '🍚'],
  [['توابل', 'بهارات', 'spice', 'season'], '🧂'],
  [['مكسرات', 'تمور', 'nuts', 'dates'], '🥜'],
  [['حيوانات', 'pet'], '🐾'],
]

export function categoryGlyph(name: string): string {
  const n = name.toLowerCase()
  for (const [words, glyph] of RULES) if (words.some((w) => n.includes(w))) return glyph
  return '🛒'
}
