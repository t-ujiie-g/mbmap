// Text layout of point labels, in CSS pixels relative to the anchor (y down).
// Import-free so tests run it as is.

// Glyph metrics come from TinySDF drawn at SDF_SIZE px with SDF_BUFFER px of
// padding around each bitmap.
export const SDF_SIZE = 48;
export const SDF_BUFFER = 6;
export const SDF_RADIUS = 16;

// `@style.TextAnchor` order (worker/labels.mbt `anchor_code`).
const ANCHORS = ["center", "left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right"];

// The em box's share above the baseline.
const ASCENT = 0.88;

// Japanese line-breaking rules (kinsoku): no break before closing marks and
// small kana, none after opening brackets.
const NO_BREAK_BEFORE = new Set([..."、。，．）」』】〉》〕｝！？ー・：；ぁぃぅぇぉっゃゅょァィゥェォッャュョ︑︒︶﹂﹄︼︾︺"]);
const NO_BREAK_AFTER = new Set([..."（「『【〈《〔｛︵﹁﹃︻︽︹"]);
const ideographic = (cp) => cp >= 0x2e80;

// Characters that stand upright in vertical text (a subset of UAX #50's U and
// Tu: CJK, kana, Hangul, full-width and vertical forms); the rest lie sideways,
// as does the prolonged sound mark.
const UPRIGHT = [[0x1100, 0x11ff], [0x2e80, 0x303f], [0x3040, 0x31ff], [0x3200, 0x9fff], [0xa000, 0xa4cf],
  [0xac00, 0xd7af], [0xf900, 0xfaff], [0xfe10, 0xfe1f], [0xfe30, 0xfe4f], [0xff00, 0xffef], [0x20000, 0x3ffff]];
const upright = (cp) => cp !== 0x30fc && UPRIGHT.some(([a, b]) => cp >= a && cp <= b);

// MapLibre's vertical forms of punctuation (util/verticalize_punctuation.ts).
const VERTICAL_FORMS = new Map(Object.entries({
  "!": "︕", "#": "＃", "$": "＄", "%": "％", "&": "＆", "(": "︵", ")": "︶", "*": "＊", "+": "＋", ",": "︐",
  "-": "︲", ".": "・", "/": "／", ":": "︓", ";": "︔", "<": "︿", "=": "＝", ">": "﹀", "?": "︖", "@": "＠",
  "[": "﹇", "\\": "＼", "]": "﹈", "^": "＾", "_": "︳", "`": "｀", "{": "︷", "|": "―", "}": "︸", "~": "～",
  "¢": "￠", "£": "￡", "¥": "￥", "¦": "￤", "¬": "￢", "¯": "￣", "–": "︲", "—": "︱", "‘": "﹃", "’": "﹄",
  "“": "﹁", "”": "﹂", "…": "︙", "⋯": "︙", "‧": "・", "₩": "￦", "、": "︑", "。": "︒", "〈": "︿", "〉": "﹀",
  "《": "︽", "》": "︾", "「": "﹁", "」": "﹂", "『": "﹃", "』": "﹄", "【": "︻", "】": "︼", "〔": "︹", "〕": "︺",
  "〖": "︗", "〗": "︘", "！": "︕", "（": "︵", "）": "︶", "，": "︐", "－": "︲", "．": "・", "：": "︓", "；": "︔",
  "＜": "︿", "＞": "﹀", "？": "︖", "［": "﹇", "］": "﹈", "＿": "︳", "｛": "︷", "｜": "―", "｝": "︸", "｟": "︵",
  "｠": "︶", "｡": "︒", "｢": "﹁", "｣": "﹂",
}).map(([k, v]) => [k.codePointAt(0), v.codePointAt(0)]));

// Punctuation in its vertical form, unless a neighbour lies sideways (MapLibre's rule).
function verticalize(cps) {
  const sideways = (cp) => cp !== undefined && !upright(cp) && !VERTICAL_FORMS.has(cp);
  return cps.map((cp, i) => (VERTICAL_FORMS.has(cp) && !sideways(cps[i - 1]) && !sideways(cps[i + 1]) ? VERTICAL_FORMS.get(cp) : cp));
}

/**
 * Lays `text` out at `size` px like MapLibre, in columns when `vertical` and it has upright
 * characters; `metrics(cp)` is at SDF_SIZE. Returns quads (bitmap corners from top-left, clockwise) and the box.
 */
export function layoutLabel(text, size, { anchor = 0, offset = [0, 0], maxWidth = 10, lineHeight = 1.2, vertical = false }, metrics) {
  const scale = size / SDF_SIZE;
  let cps = [...text].map((c) => c.codePointAt(0));
  const columns = vertical && cps.some(upright);
  if (columns) cps = verticalize(cps);
  const advance = (cp) => (columns && upright(cp) ? size : metrics(cp).advance * scale);
  const lines = breakLines(cps, maxWidth * size, advance);
  const lengths = lines.map((l) => l.reduce((w, cp) => w + advance(cp), 0));
  const across = lines.length * lineHeight * size;
  const along = Math.max(0, ...lengths);
  const [width, height] = columns ? [across, along] : [along, across];
  const name = ANCHORS[anchor] ?? "center";
  const ax = name.endsWith("left") ? 0 : name.endsWith("right") ? -width : -width / 2;
  const ay = name.startsWith("top") ? 0 : name.startsWith("bottom") ? -height : -height / 2;
  const x0 = ax + offset[0] * size;
  const y0 = ay + offset[1] * size;
  const justify = columns
    ? (name.startsWith("top") ? 0 : name.startsWith("bottom") ? 1 : 0.5)
    : (name.endsWith("left") ? 0 : name.endsWith("right") ? 1 : 0.5);
  const quads = [];
  // A glyph's padded bitmap against its pen and baseline, before any turn.
  const rect = (m) => [m.left * scale, -m.top * scale, (m.left + m.width) * scale, (m.height - m.top) * scale];
  const inked = (m) => m.width > 2 * SDF_BUFFER && m.height > 2 * SDF_BUFFER;
  // An unturned glyph with its pen at x and its baseline at y.
  const standing = (cp, m, x, y) => {
    const [l, t, r, b] = rect(m);
    return { cp, corners: [[x + l, y + t], [x + r, y + t], [x + r, y + b], [x + l, y + b]] };
  };
  lines.forEach((line, i) => {
    let pen = (along - lengths[i]) * justify;
    if (!columns) {
      const baseline = y0 + i * lineHeight * size + ((lineHeight - 1) * size) / 2 + ASCENT * size;
      pen += x0;
      for (const cp of line) {
        const m = metrics(cp);
        if (inked(m)) quads.push(standing(cp, m, pen, baseline));
        pen += m.advance * scale;
      }
      return;
    }
    // Columns run right to left; each character takes its advance down the column.
    const center = x0 + width - (i + 0.5) * lineHeight * size;
    pen += y0;
    for (const cp of line) {
      const m = metrics(cp);
      if (inked(m) && upright(cp)) {
        quads.push(standing(cp, m, center - (m.advance * scale) / 2, pen + ASCENT * size));
      } else if (inked(m)) {
        // Turned a quarter clockwise, the em box centered on the column.
        const [l, t, r, b] = rect(m);
        const x = center + (ASCENT - 0.5) * size;
        quads.push({ cp, corners: [[x - t, pen + l], [x - t, pen + r], [x - b, pen + r], [x - b, pen + l]] });
      }
      pen += advance(cp);
    }
  });
  return { quads, box: [x0, y0, x0 + width, y0 + height] };
}

// Greedy line breaking: `\n` always breaks; past `limit`, the line breaks at
// its last opportunity (a space, which is dropped, or between ideographs).
function breakLines(cps, limit, advance) {
  const lines = [];
  let line = [];
  let width = 0;
  let cut = -1;
  const canBreakBefore = (prev, cp) =>
    !NO_BREAK_BEFORE.has(String.fromCodePoint(cp)) && !NO_BREAK_AFTER.has(String.fromCodePoint(prev)) && (ideographic(cp) || ideographic(prev));
  for (const cp of cps) {
    if (cp === 10) {
      lines.push(line);
      line = [];
      width = 0;
      cut = -1;
      continue;
    }
    if (cp === 32) cut = line.length;
    else if (line.length > 0 && canBreakBefore(line[line.length - 1], cp)) cut = line.length;
    line.push(cp);
    width += advance(cp);
    if (width > limit && cut > 0) {
      const rest = line.slice(line[cut] === 32 ? cut + 1 : cut);
      lines.push(line.slice(0, cut));
      line = rest;
      width = rest.reduce((w, c) => w + advance(c), 0);
      cut = -1;
    }
  }
  lines.push(line);
  return lines.map((l) => (l[l.length - 1] === 32 ? l.slice(0, -1) : l)).filter((l, _, all) => l.length > 0 || all.length === 1);
}
