// Azir Market — builds the supermarket storefront screens as native, editable
// Figma layers (frames, rectangles, text), using the exact tokens of the
// Flutter implementation (flutter/lib/features/grocery/grocery_theme.dart).
//
// Run once from Figma: Plugins → Development → Import plugin from manifest…
// → pick manifest.json → Run. Re-run any time: it adds a fresh page.
//
// Units are iOS points (402 × 874 = iPhone 17 Pro). Layout is RTL: x positions
// are computed from the right edge, exactly like the app.

// ---------------------------------------------------------------- tokens ----
const W = 402;
const H = 874;
const STATUS_TOP = 59; // status bar / Dynamic Island inset
const SAFE_BOTTOM = 34; // home indicator inset

const C = {
  bg: '#FFFFFF',
  surface: '#FFFFFF',
  surface2: '#F3F4F6',
  line: '#EDEEF0',
  ink: '#111827',
  ink2: '#4B5563',
  ink3: '#9CA3AF',
  accent: '#0D9488',
  accentDeep: '#0F766E',
  red: '#E5484D',
  bannerDark: '#0B3B33',
  bannerDark2: '#166353',
  bannerLime: '#8DE3C4',
  bannerSub: '#D6EFE4',
  openBg: '#E7F6EE',
  openInk: '#1D8251',
  white: '#FFFFFF',
};

const S = { s4: 4, s8: 8, s12: 12, s16: 16, s24: 24, s32: 32 };
const PAGE_X = 12;
const HEADER_X = 16;
const GUTTER = 8;
const CARD_R = 12;
const NAV_H = 64;

const FONT_FAMILY = 'IBM Plex Sans Arabic';

// ---------------------------------------------------------------- demo data --
// The demo store (سوق البركة). Replace freely — layout adapts to text length.
const CATEGORIES = [
  { name: 'خضار وفواكه', glyph: '🍅' },
  { name: 'ألبان وبيض', glyph: '🥛' },
  { name: 'مخبوزات', glyph: '🥐' },
  { name: 'سناكات', glyph: '🍿' },
  { name: 'مشروبات', glyph: '🧃' },
  { name: 'منظفات ومنزل', glyph: '🧴' },
];

const BEST = [
  { name: 'موز', unit: '1 كجم', price: '5.95', old: '6.95', off: 14, glyph: '🍌' },
  { name: 'تفاح أحمر', unit: '1 كجم', price: '8.95', glyph: '🍎' },
  { name: 'حليب طازج', unit: '1 لتر', price: '6.25', old: '7.50', off: 17, glyph: '🥛' },
  { name: 'بيض بلدي', unit: '12 حبة', price: '17.95', old: '19.95', off: 10, glyph: '🥚' },
];

const PRODUCE = [
  { name: 'موز', unit: '1 كجم', price: '5.95', old: '6.95', off: 14, glyph: '🍌' },
  { name: 'طماطم', unit: '1 كجم', price: '4.50', glyph: '🍅' },
  { name: 'خيار', unit: '1 كجم', price: '3.95', glyph: '🥒' },
  { name: 'ليمون', unit: '1 كجم', price: '7.50', old: '8.95', off: 16, glyph: '🍋' },
  { name: 'تفاح أحمر', unit: '1 كجم', price: '8.95', glyph: '🍎' },
];

const DAIRY = [
  { name: 'حليب طازج', unit: '1 لتر', price: '6.25', old: '7.50', off: 17, glyph: '🥛' },
  { name: 'بيض بلدي', unit: '12 حبة', price: '17.95', old: '19.95', off: 10, glyph: '🥚' },
  { name: 'لبن', unit: '1 لتر', price: '5.50', glyph: '🥛' },
  { name: 'جبن شرائح', unit: '200 جم', price: '12.95', glyph: '🧀' },
];

// ---------------------------------------------------------------- helpers ---
function hex(h) {
  const n = parseInt(h.slice(1), 16);
  return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 };
}
const solid = (h, opacity) => ({ type: 'SOLID', color: hex(h), opacity: opacity == null ? 1 : opacity });

function rect(parent, x, y, w, h, opts) {
  const o = opts || {};
  const r = figma.createRectangle();
  r.name = o.name || 'Rect';
  r.x = x;
  r.y = y;
  r.resize(Math.max(w, 0.01), Math.max(h, 0.01));
  r.fills = o.fill === 'none' ? [] : [solid(o.fill || C.surface, o.opacity)];
  if (o.gradient) r.fills = [o.gradient];
  if (o.radius != null) r.cornerRadius = o.radius;
  if (o.stroke) {
    r.strokes = [solid(o.stroke)];
    r.strokeWeight = o.strokeWeight || 1;
    r.strokeAlign = 'INSIDE';
  }
  if (o.shadow) {
    r.effects = [{
      type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: 0.06 },
      offset: { x: 0, y: 3 }, radius: 10, spread: 0, visible: true, blendMode: 'NORMAL',
    }];
  }
  parent.appendChild(r);
  return r;
}

function ellipse(parent, x, y, d, opts) {
  const o = opts || {};
  const e = figma.createEllipse();
  e.name = o.name || 'Circle';
  e.x = x;
  e.y = y;
  e.resize(d, d);
  e.fills = [solid(o.fill || C.surface)];
  if (o.stroke) {
    e.strokes = [solid(o.stroke)];
    e.strokeWeight = o.strokeWeight || 1;
    e.strokeAlign = 'INSIDE';
  }
  if (o.shadow) {
    e.effects = [{
      type: 'DROP_SHADOW', color: { r: 0, g: 0, b: 0, a: 0.15 },
      offset: { x: 0, y: 1 }, radius: 3, spread: 0, visible: true, blendMode: 'NORMAL',
    }];
  }
  parent.appendChild(e);
  return e;
}

let fontStyles = {}; // weight -> style name actually available

async function loadFonts() {
  // Map CSS-ish weights onto the family's styles; fall back to Inter.
  const want = { 400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'Bold' };
  for (const w of Object.keys(want)) {
    const style = want[w];
    try {
      await figma.loadFontAsync({ family: FONT_FAMILY, style });
      fontStyles[w] = { family: FONT_FAMILY, style };
    } catch (e) {
      const fb = { family: 'Inter', style: style === 'SemiBold' ? 'Semi Bold' : style };
      await figma.loadFontAsync(fb);
      fontStyles[w] = fb;
    }
  }
}

// A text box whose right edge is at `right` (RTL), or left edge at `left`.
function text(parent, str, opts) {
  const o = opts || {};
  const t = figma.createText();
  t.name = o.name || str.slice(0, 24);
  t.fontName = fontStyles[o.weight || 400];
  t.characters = str;
  t.fontSize = o.size || 13;
  t.fills = [solid(o.color || C.ink)];
  if (o.lineHeight) t.lineHeight = { value: o.lineHeight * 100, unit: 'PERCENT' };
  if (o.strike) t.textDecoration = 'STRIKETHROUGH';
  if (o.letterSpacing) t.letterSpacing = { value: o.letterSpacing, unit: 'PIXELS' };
  if (o.width) {
    t.textAutoResize = 'HEIGHT';
    t.resize(o.width, 10);
  } else {
    t.textAutoResize = 'WIDTH_AND_HEIGHT';
  }
  t.textAlignHorizontal = o.align || (o.left != null ? 'LEFT' : 'RIGHT');
  if (o.maxLines) {
    t.textTruncation = 'ENDING';
    t.maxLines = o.maxLines;
  }
  parent.appendChild(t);
  t.y = o.y || 0;
  if (o.left != null) t.x = o.left;
  else if (o.centerX != null) t.x = o.centerX - t.width / 2;
  else t.x = (o.right == null ? W : o.right) - t.width;
  return t;
}

function frame(parent, name, x, y, w, h, fill) {
  const f = figma.createFrame();
  f.name = name;
  f.x = x;
  f.y = y;
  f.resize(w, h);
  f.fills = fill === 'none' ? [] : [solid(fill || C.bg)];
  f.clipsContent = true;
  if (parent) parent.appendChild(f);
  return f;
}

const bannerGradient = () => ({
  type: 'GRADIENT_LINEAR',
  gradientTransform: [[1, 0, 0], [0, 1, 0]],
  gradientStops: [
    { position: 0, color: Object.assign(hex(C.bannerDark), { a: 1 }) },
    { position: 1, color: Object.assign(hex(C.bannerDark2), { a: 1 }) },
  ],
});

const tileGradient = () => ({
  type: 'GRADIENT_LINEAR',
  gradientTransform: [[0, 1, 0], [-1, 0, 1]],
  gradientStops: [
    { position: 0, color: Object.assign(hex(C.surface2), { a: 1 }) },
    { position: 1, color: Object.assign(hex('#FAFAFB'), { a: 1 }) },
  ],
});

// ---------------------------------------------------------------- pieces ----
function roundButton(parent, x, y, glyph, opts) {
  const o = opts || {};
  const g = frame(parent, o.name || 'Round button', x, y, 40, 40, 'none');
  g.clipsContent = false;
  ellipse(g, 0, 0, 40, { fill: C.surface2 });
  text(g, glyph, { size: 18, color: C.ink, centerX: 20, y: 9, align: 'CENTER', name: 'icon' });
  return g;
}

// Product card, width `w`; returns its height.
function productCard(parent, x, y, w, p, nameLines) {
  const card = frame(parent, 'Product / ' + p.name, x, y, w, 10, 'none');
  card.clipsContent = false;
  // Tile
  rect(card, 0, 0, w, w, { name: 'Tile', fill: C.surface, radius: CARD_R, stroke: C.line, shadow: true });
  text(card, p.glyph, { size: Math.round(w * 0.42), centerX: w / 2, y: w * 0.22, align: 'CENTER', name: 'photo' });
  if (p.off) {
    const b = frame(card, 'Badge / discount', 0, 6, 10, 18, C.red);
    b.cornerRadius = 8;
    const bt = text(b, 'خصم ' + p.off + '%', { size: 10, weight: 800, color: C.white, left: 6, y: 2.5 });
    b.resize(bt.width + 12, 18);
    b.x = w - 6 - b.width; // top-start (right in RTL)
  }
  // "+" bottom-end (left in RTL)
  const plus = frame(card, 'Add', 6, w - 6 - 28, 28, 28, 'none');
  plus.clipsContent = false;
  ellipse(plus, 0, 0, 28, { fill: C.white, shadow: true });
  text(plus, '+', { size: 18, weight: 500, color: C.ink, centerX: 14, y: 2, align: 'CENTER' });
  // Price line (right-aligned)
  let py = w + S.s8;
  const price = text(card, p.price + ' ﷼', {
    size: 15, weight: 800, color: p.off ? C.red : C.ink, right: w, y: py, name: 'price',
  });
  if (p.old) {
    text(card, p.old + ' ﷼', {
      size: 11.5, color: C.ink3, strike: true, right: w - price.width - 6, y: py + 3, name: 'old price',
    });
  }
  // Name (up to 2 lines) + unit
  py += 20 + S.s4;
  const name = text(card, p.name, {
    size: 13, weight: 600, color: C.ink, width: w, y: py, lineHeight: 1.35, maxLines: 2, name: 'name',
  });
  name.x = 0;
  py += 18 * nameLines + 2;
  if (p.unit) text(card, p.unit, { size: 11, color: C.ink3, right: w, y: py, lineHeight: 1.25, name: 'unit' });
  const h = w + S.s8 + 20 + S.s4 + 18 * nameLines + 2 + 14 + 1;
  card.resize(w, h);
  return h;
}

function sectionTitle(parent, y, title, withSeeAll) {
  text(parent, title, { size: 16, weight: 800, color: C.ink, right: W - PAGE_X, y, name: 'Section title' });
  if (withSeeAll) text(parent, '← عرض الكل', { size: 12.5, weight: 600, color: C.accent, left: PAGE_X, y: y + 3 });
  return y + 20 + S.s12;
}

function grid(parent, y, items, cols, left, right) {
  const avail = W - left - right;
  const cellW = (avail - GUTTER * (cols - 1)) / cols;
  let rowH = 0;
  items.forEach((p, i) => {
    const col = i % cols;
    const row = Math.floor(i / cols);
    const x = W - right - cellW - col * (cellW + GUTTER); // RTL: first column at the right
    const h = productCard(parent, x, y + row * (rowH + S.s16), cellW, p, 1);
    rowH = h;
  });
  const rows = Math.ceil(items.length / cols);
  return y + rows * rowH + (rows - 1) * S.s16;
}

function navBar(parent, active) {
  const y = H - SAFE_BOTTOM - NAV_H;
  const bar = frame(parent, 'Nav bar', 0, y, W, NAV_H + SAFE_BOTTOM, 'none');
  const bg = rect(bar, 0, 0, W, NAV_H + SAFE_BOTTOM, { fill: C.surface, opacity: 0.86 });
  bg.topLeftRadius = 24;
  bg.topRightRadius = 24;
  bg.strokes = [solid(C.line)];
  bg.strokeWeight = 1;
  bg.strokeAlign = 'INSIDE';
  const tabs = [
    ['الرئيسية', '⌂'], ['الأقسام', '▦'], ['السلة', '🛒'], ['طلباتي', '🧾'], ['حسابي', '👤'],
  ];
  const colW = W / tabs.length;
  tabs.forEach((t, i) => {
    const cx = W - colW * i - colW / 2; // RTL order
    const color = i === active ? C.accent : C.ink3;
    text(bar, t[1], { size: 20, color, centerX: cx, y: 12, align: 'CENTER', name: 'icon' });
    text(bar, t[0], { size: 11, weight: i === active ? 700 : 500, color, centerX: cx, y: 40, align: 'CENTER' });
  });
  return bar;
}

function statusBar(parent) {
  text(parent, '9:41', { size: 15, weight: 600, color: C.ink, left: 36, y: 18 });
  rect(parent, W / 2 - 62, 11, 124, 36, { fill: '#000000', radius: 18, name: 'Dynamic Island' });
  text(parent, '●●● ▲ ▮', { size: 11, color: C.ink, right: W - 28, y: 20, name: 'indicators' });
}

// ---------------------------------------------------------------- screens ---
function buildHome(parent, x0, y0, fullHeight) {
  const home = frame(parent, fullHeight ? 'Home – full scroll' : 'Home', x0, y0, W, H, C.bg);
  let y = STATUS_TOP + S.s8;

  // Top row
  roundButton(home, W - HEADER_X - 40, y, '→', { name: 'Back' });
  const av = rect(home, W - HEADER_X - 40 - S.s8 - 32, y + 4, 32, 32, { fill: '#1F6B4A', radius: 8, name: 'Store avatar' });
  text(home, 'س', { size: 15, weight: 700, color: C.white, centerX: av.x + 16, y: y + 10, align: 'CENTER' });
  text(home, 'سوق البركة', { size: 15, weight: 700, color: C.ink, right: av.x - S.s8, y: y + 9, name: 'Store name' });
  const open = frame(home, 'Open badge', 0, y + 9, 10, 22, C.openBg);
  open.cornerRadius = 11;
  const ot = text(open, '• مفتوح', { size: 11, weight: 600, color: C.openInk, left: 8, y: 3 });
  open.resize(ot.width + 16, 22);
  open.x = HEADER_X + 40 + S.s8;
  roundButton(home, HEADER_X, y, '🔔', { name: 'Notifications' });
  y += 40 + S.s16;

  // Hero
  const heroImg = rect(home, HEADER_X, y, 112, 112, { gradient: bannerGradient(), radius: 16, name: 'Store cover' });
  text(home, '🥦🍅\n🥛🍋', { size: 30, centerX: heroImg.x + 56, y: y + 18, align: 'CENTER', lineHeight: 1.25, name: 'cover art' });
  const textRight = W - HEADER_X;
  text(home, 'أهلاً بك 👋', { size: 13, weight: 600, color: C.accent, right: textRight, y: y + 4 });
  text(home, 'احتياجاتك اليومية', { size: 24, weight: 800, color: C.ink, right: textRight, y: y + 24, lineHeight: 1.15 });
  text(home, 'تصلك إلى بابك', { size: 24, weight: 800, color: C.accent, right: textRight, y: y + 52, lineHeight: 1.15 });
  text(home, 'خضار، بقالة، ومنتجات طازجة بلمسة واحدة.', {
    size: 12.5, color: C.ink2, width: W - HEADER_X * 2 - 112 - S.s12, y: y + 88, lineHeight: 1.45, maxLines: 2,
  }).x = HEADER_X + 112 + S.s12;
  y += 112 + S.s16;

  // Search row
  const field = rect(home, HEADER_X + 44 + S.s8, y, W - HEADER_X * 2 - 44 - S.s8, 44, { fill: C.surface2, radius: CARD_R, name: 'Search field' });
  text(home, 'ابحث عن منتج…', { size: 14, color: C.ink3, right: field.x + field.width - 40, y: y + 12 });
  text(home, '⌕', { size: 20, color: C.ink3, right: field.x + field.width - 12, y: y + 9, name: 'search icon' });
  rect(home, HEADER_X, y, 44, 44, { fill: C.accent, radius: CARD_R, name: 'Filter button' });
  text(home, '⚌', { size: 18, color: C.white, centerX: HEADER_X + 22, y: y + 11, align: 'CENTER', name: 'filter icon' });
  y += 44 + S.s16;

  // Category tiles (60 rounded squares, 72 wide items, 8 apart)
  CATEGORIES.forEach((c, i) => {
    const ix = W - PAGE_X - 72 - i * (72 + S.s8);
    const tile = rect(home, ix + 6, y, 60, 60, {
      gradient: tileGradient(), radius: 16, stroke: i === 0 ? C.accent : C.line, strokeWeight: 1.5, name: 'Category tile',
    });
    text(home, c.glyph, { size: 28, centerX: tile.x + 30, y: y + 13, align: 'CENTER' });
    text(home, c.name, { size: 11.5, weight: 700, color: C.ink, width: 72, y: y + 60 + S.s8, align: 'CENTER', lineHeight: 1.2, maxLines: 2 }).x = ix;
  });
  y += 96 + S.s16;

  // Promo banner (shown when the merchant has a cover/pop-up photo)
  const bh = Math.round((W - PAGE_X * 2) / 2.3);
  const banner = frame(home, 'Promo banner', PAGE_X, y, W - PAGE_X * 2, bh, 'none');
  banner.cornerRadius = CARD_R;
  rect(banner, 0, 0, banner.width, bh, { gradient: bannerGradient(), name: 'photo + wash' });
  text(banner, '🍅🥦\n🥕🥛\n🍇🍓', { size: 34, left: 14, y: 6, align: 'CENTER', lineHeight: 1.2, name: 'photo art' });
  ellipse(banner, 12, 12, 28, { fill: C.accent, name: 'Star badge' });
  text(banner, '★', { size: 14, color: C.white, centerX: 26, y: 17, align: 'CENTER' });
  const br = banner.width - S.s16;
  text(banner, 'عرض خاص', { size: 10.5, weight: 800, color: C.bannerLime, right: br, y: 40, letterSpacing: 0.6 });
  text(banner, 'خصم حتى 17%', { size: 20, weight: 800, color: C.white, right: br, y: 58, lineHeight: 1.15 });
  text(banner, 'على ألبان وبيض', { size: 12, weight: 600, color: C.bannerSub, right: br, y: 84 });
  const btn = frame(banner, 'Shop now', 0, 108, 10, 32, C.accent);
  btn.cornerRadius = 16;
  const bt = text(btn, '← تسوّق الآن', { size: 12, weight: 800, color: C.white, left: 12, y: 8 });
  btn.resize(bt.width + 24, 32);
  btn.x = banner.width - S.s16 - btn.width;
  y += bh + S.s24;

  // Best sellers strip (same cell size as the grid)
  y = sectionTitle(home, y, 'الأكثر مبيعاً', true);
  const cellW = (W - PAGE_X * 2 - GUTTER * 2) / 3;
  let stripH = 0;
  BEST.forEach((p, i) => {
    const cx = W - PAGE_X - cellW - i * (cellW + GUTTER);
    stripH = productCard(home, cx, y, cellW, p, 1);
  });
  y += stripH + S.s24;

  // Category sections
  y = sectionTitle(home, y, 'خضار وفواكه', true);
  y = grid(home, y, PRODUCE, 3, PAGE_X, PAGE_X) + S.s24;
  y = sectionTitle(home, y, 'ألبان وبيض', true);
  y = grid(home, y, DAIRY, 3, PAGE_X, PAGE_X) + S.s24;

  // Features card
  const fc = frame(home, 'Features card', PAGE_X, y, W - PAGE_X * 2, 84, C.surface);
  fc.cornerRadius = CARD_R;
  fc.strokes = [solid(C.line)];
  fc.strokeWeight = 1;
  const feats = [['🛵', 'توصيل سريع', 'يصلك خلال دقائق'], ['🏷️', 'أفضل الأسعار', 'خصومات حصرية'], ['🌿', 'طازج 100%', 'جودة تثق بها']];
  const fw = fc.width / 3;
  feats.forEach((f, i) => {
    const cx = fc.width - fw * i - fw / 2;
    text(fc, f[0], { size: 22, centerX: cx, y: 12, align: 'CENTER' });
    text(fc, f[1], { size: 12, weight: 700, color: C.ink, centerX: cx, y: 44, align: 'CENTER' });
    text(fc, f[2], { size: 10.5, color: C.ink3, centerX: cx, y: 62, align: 'CENTER' });
  });
  y += 84 + S.s24 + NAV_H + SAFE_BOTTOM;

  if (fullHeight) home.resize(W, y);
  else navBar(home, 0);
  statusBar(home);
  return home;
}

function buildDocked(parent, x0, y0) {
  // The search row + text-only category chips, as they dock under the status
  // bar once the page scrolls (reference: sticky tools).
  const f = frame(parent, 'Docked tools (on scroll)', x0, y0, W, STATUS_TOP + S.s8 + 44 + S.s8 + 36 + S.s8 + 1, C.bg);
  let y = STATUS_TOP + S.s8;
  const field = rect(f, HEADER_X + 44 + S.s8, y, W - HEADER_X * 2 - 44 - S.s8, 44, { fill: C.surface2, radius: CARD_R, name: 'Search field' });
  text(f, 'ابحث عن منتج…', { size: 14, color: C.ink3, right: field.x + field.width - 40, y: y + 12 });
  text(f, '⌕', { size: 20, color: C.ink3, right: field.x + field.width - 12, y: y + 9 });
  rect(f, HEADER_X, y, 44, 44, { fill: C.accent, radius: CARD_R, name: 'Filter button' });
  text(f, '⚌', { size: 18, color: C.white, centerX: HEADER_X + 22, y: y + 11, align: 'CENTER' });
  y += 44 + S.s8;
  let right = W - PAGE_X;
  CATEGORIES.forEach((c) => {
    const chip = frame(f, 'Chip / ' + c.name, 0, y, 10, 36, C.surface2);
    chip.cornerRadius = 4;
    const t = text(chip, c.name, { size: 12.5, weight: 600, color: C.ink, left: 12, y: 9 });
    chip.resize(t.width + 24, 36);
    chip.x = right - chip.width;
    right = chip.x - S.s8;
  });
  rect(f, 0, f.height - 1, W, 1, { fill: C.line, name: 'hairline' });
  statusBar(f);
  return f;
}

function buildCategories(parent, x0, y0) {
  const scr = frame(parent, 'Categories', x0, y0, W, H, C.bg);
  let y = STATUS_TOP + S.s8;
  roundButton(scr, W - HEADER_X - 40, y, '→', { name: 'Back' });
  text(scr, 'الأقسام', { size: 19, weight: 800, color: C.ink, right: W - HEADER_X - 40 - S.s12, y: y + 8 });
  y += 40 + S.s12;

  // Side rail (right): 12 margin + 72 item + 12 gutter
  const railX = W - PAGE_X - 72;
  const rail = [{ name: 'الأكثر مبيعاً', glyph: '🔥' }].concat(CATEGORIES);
  let ry = y;
  rail.forEach((c, i) => {
    const item = frame(scr, 'Rail / ' + c.name, railX, ry, 72, 10, i === 0 ? C.surface2 : 'none');
    item.cornerRadius = CARD_R;
    if (i === 0) {
      item.strokes = [solid(C.accent)];
      item.strokeWeight = 1.5;
    }
    rect(item, 14, 8, 44, 44, { fill: C.surface, radius: 12, name: 'tile' });
    text(item, c.glyph, { size: 22, centerX: 36, y: 18, align: 'CENTER' });
    const lbl = text(item, c.name, { size: 10.5, weight: i === 0 ? 700 : 500, color: i === 0 ? C.ink : C.ink2, width: 64, y: 56, align: 'CENTER', lineHeight: 1.2, maxLines: 2 });
    lbl.x = 4;
    item.resize(72, 56 + lbl.height + 8);
    ry += item.height + S.s8;
  });

  // Title row + two-column grid in the remaining width
  const gridRight = PAGE_X + 72 + S.s12;
  text(scr, 'الأكثر مبيعاً', { size: 16, weight: 800, color: C.ink, right: W - gridRight, y });
  text(scr, '6', { size: 12.5, color: C.ink3, left: PAGE_X, y: y + 4 });
  y += 20 + S.s12;
  grid(scr, y, BEST.concat([PRODUCE[3], DAIRY[3]]), 2, PAGE_X, gridRight);

  navBar(scr, 1);
  statusBar(scr);
  return scr;
}

function buildTokens(parent, x0, y0) {
  const f = frame(parent, 'Design tokens', x0, y0, 420, 560, C.bg);
  f.strokes = [solid(C.line)];
  f.strokeWeight = 1;
  text(f, 'Azir Market — tokens', { size: 16, weight: 700, color: C.ink, left: 16, y: 16, align: 'LEFT' });
  const rows = [
    ['Canvas', C.bg], ['Surface 2 (inputs, chips)', C.surface2], ['Hairline', C.line],
    ['Ink', C.ink], ['Ink 2', C.ink2], ['Ink 3', C.ink3],
    ['Accent (teal)', C.accent], ['Accent deep', C.accentDeep], ['Sale red', C.red],
    ['Banner dark', C.bannerDark], ['Banner lime', C.bannerLime],
  ];
  rows.forEach((r, i) => {
    const y = 52 + i * 34;
    rect(f, 16, y, 28, 28, { fill: r[1], radius: 8, stroke: C.line });
    text(f, r[0] + '   ' + r[1], { size: 12.5, color: C.ink, left: 56, y: y + 6, align: 'LEFT' });
  });
  const notes = [
    'Spacing: 4 / 8 / 12 / 16 / 24 (8pt grid)',
    'Page margin 12, header 16, gutter 8, row gap 16',
    'Radius: cards 12, category tiles 16, chips 4, pills round',
    'Type: IBM Plex Sans Arabic — hero 24/800, title 16/800,',
    'price 15/800, name 13/600, unit 11, label 11.5/700',
  ];
  notes.forEach((n, i) => text(f, n, { size: 12, color: C.ink2, left: 16, y: 440 + i * 20, align: 'LEFT' }));
  return f;
}

// ---------------------------------------------------------------- main ------
async function main() {
  await loadFonts();
  const page = figma.createPage();
  page.name = 'Azir Market — supermarket';
  await figma.setCurrentPageAsync(page);

  // Colour styles, so every fill is relinkable from Figma's panel.
  const styleNames = {
    bg: 'Canvas', surface2: 'Surface 2', line: 'Hairline', ink: 'Ink', ink2: 'Ink 2', ink3: 'Ink 3',
    accent: 'Accent', accentDeep: 'Accent deep', red: 'Sale red', bannerDark: 'Banner dark', bannerLime: 'Banner lime',
  };
  for (const k of Object.keys(styleNames)) {
    const s = figma.createPaintStyle();
    s.name = 'Azir Market/' + styleNames[k];
    s.paints = [solid(C[k])];
  }

  const gap = 80;
  const home = buildHome(page, 0, 0, false);
  const docked = buildDocked(page, W + gap, 0);
  const cats = buildCategories(page, (W + gap) * 2, 0);
  const full = buildHome(page, (W + gap) * 3, 0, true);
  const tokens = buildTokens(page, (W + gap) * 4, 0);

  figma.viewport.scrollAndZoomIntoView([home, docked, cats, full, tokens]);
  figma.notify('Azir Market: 5 frames built on page "Azir Market — supermarket".');
  figma.closePlugin();
}

main().catch((e) => {
  figma.notify('Azir Market plugin failed: ' + (e && e.message ? e.message : e), { error: true });
  figma.closePlugin();
});
