// Text layout of point labels, in CSS pixels relative to the anchor (y down).
// Import-free so tests run it as is.

// Glyph metrics come from TinySDF drawn at SDF_SIZE px with SDF_BUFFER px of
// padding around each bitmap.
export const SDF_SIZE = 48;
export const SDF_BUFFER = 6;
export const SDF_RADIUS = 16;

// `@style.TextAnchor` order (`TextAnchor::code` in style/anchor.mbt).
const ANCHORS = ["center", "left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right"];

// The em box's share above the baseline.
const ASCENT = 0.88;
// MapLibre's glyph units per em (`ONE_EM`), in which it breaks lines.
const ONE_EM = 24;

// MapLibre's line breaking (symbol/tagged_string.ts): characters a line may end
// on, and those after which it may break between ideographs
// (`codePointAllowsIdeographicBreaking`).
const BREAKABLE = new Set([0x0a, 0x0d, 0x20, 0x26, 0x29, 0x2b, 0x2d, 0x2f, 0xad, 0xb7, 0x200b, 0x2010, 0x2013, 0x2027]);
const IDEOGRAPHIC_BREAK = /[˪˫⺀-⿟⿰-〿ぁ-ゖゝ-ゟァ-ヺヽ-ヿㄅ-ㄯㆠ-䶿一-ꒌ꒐-꓆豈-舘並-龎︐-︟︰-﹏＀-￯]|\uD81B[\uDFE0-\uDFFF]|[\uD81C-\uD822\uD840-\uD868\uD86A-\uD86D\uD86F-\uD872\uD874-\uD879\uD880-\uD883\uD885-\uD88C][\uDC00-\uDFFF]|\uD823[\uDC00-\uDCD5\uDCFF-\uDD1E\uDD80-\uDDF2]|\uD82B[\uDFF0-\uDFFF]|\uD82C[\uDC00-\uDEFB]|\uD83C[\uDE00-\uDEFF]|\uD869[\uDC00-\uDEDF\uDF00-\uDFFF]|\uD86E[\uDC00-\uDC1D\uDC20-\uDFFF]|\uD873[\uDC00-\uDEAD\uDEB0-\uDFFF]|\uD87A[\uDC00-\uDFE0\uDFF0-\uDFFF]|\uD87B[\uDC00-\uDE5D]|\uD87E[\uDC00-\uDE1D]|\uD884[\uDC00-\uDF4A\uDF50-\uDFFF]|\uD88D[\uDC00-\uDC79]/i;
const ideographic = (cp) => IDEOGRAPHIC_BREAK.test(String.fromCodePoint(cp));
const whitespace = (cp) => /\s/u.test(String.fromCodePoint(cp));

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

// `text-justify` values in worker/labels.mbt's order; "auto" follows the anchor.
export const JUSTIFY = ["auto", "left", "center", "right"];

/**
 * Lays `text` out at `size` px like MapLibre, in columns when `vertical` and it has upright
 * characters; `metrics(cp)` is at SDF_SIZE. Returns quads (bitmap corners from top-left, clockwise) and the box.
 */
export function layoutLabel(text, size, { anchor = 0, offset = [0, 0], maxWidth = 10, lineHeight = 1.2, vertical = false, justify = "auto" }, metrics) {
  const scale = size / SDF_SIZE;
  let cps = [...text].map((c) => c.codePointAt(0));
  const columns = vertical && cps.some(upright);
  if (columns) cps = verticalize(cps);
  const advance = (cp) => (columns && upright(cp) ? size : metrics(cp).advance * scale);
  const lines = breakLines(cps, maxWidth * ONE_EM, (cp) => (advance(cp) * ONE_EM) / size);
  const lengths = lines.map((l) => l.reduce((w, cp) => w + advance(cp), 0));
  const across = lines.length * lineHeight * size;
  const along = Math.max(0, ...lengths);
  const [width, height] = columns ? [across, along] : [along, across];
  const name = ANCHORS[anchor] ?? "center";
  const ax = name.endsWith("left") ? 0 : name.endsWith("right") ? -width : -width / 2;
  const ay = name.startsWith("top") ? 0 : name.startsWith("bottom") ? -height : -height / 2;
  const x0 = ax + offset[0] * size;
  const y0 = ay + offset[1] * size;
  const side = justify === "auto" ? name : justify;
  const share = columns
    ? (name.startsWith("top") ? 0 : name.startsWith("bottom") ? 1 : 0.5)
    : (side.endsWith("left") ? 0 : side.endsWith("right") ? 1 : 0.5);
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
    let pen = (along - lengths[i]) * share;
    if (!columns) {
      const baseline = y0 + i * lineHeight * size + ((lineHeight - 1) * size) / 2 + ASCENT * size;
      pen += x0;
      for (const cp of line) {
        const m = metrics(cp);
        // `along`: the glyph's middle, where a label along a line puts it on the line.
        if (inked(m)) quads.push({ ...standing(cp, m, pen, baseline), along: pen + (m.advance * scale) / 2 });
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
  return { quads, box: [x0, y0, x0 + width, y0 + height], lines: lines.length };
}

// MapLibre's `calculatePenalty` and `evaluateBreak`: the break at `index`
// (pen at `x`) after the prior break that makes the lines least ragged.
function penalty(cp, next, ideographicHint) {
  return (cp === 0x0a || cp === 0x0d ? -10000 : 0) + (ideographicHint ? 150 : 0) +
    (cp === 0x28 || cp === 0xff08 ? 50 : 0) + (next === 0x29 || next === 0xff09 ? 50 : 0);
}

function evaluateBreak(index, x, target, breaks, penalty, last) {
  const badness = (width) => {
    const ragged = (width - target) ** 2;
    if (last) return width < target ? ragged / 2 : ragged * 2;
    return ragged + Math.abs(penalty) * penalty;
  };
  let prior = null;
  let best = badness(x);
  for (const b of breaks) {
    const score = badness(x - b.x) + b.badness;
    if (score <= best) {
      prior = b;
      best = score;
    }
  }
  return { index, x, prior, badness: best };
}

// MapLibre's `determineLineBreaks`, `breakLines` and `trim`: lines of about equal
// width under `limit`, `advance` and `limit` in its 24-unit em.
function breakLines(cps, limit, advance) {
  const total = cps.reduce((w, cp) => w + advance(cp), 0);
  const ends = [];
  if (total > 0 && total <= limit && !cps.includes(0x0a) && !cps.includes(0x0d)) {
    ends.push(cps.length);
  } else {
    const target = total / Math.max(1, Math.ceil(total / limit));
    const hinted = cps.includes(0x200b);
    const breaks = [];
    let x = 0;
    cps.forEach((cp, i) => {
      if (i > 0) {
        const prev = cps[i - 1];
        const ideographicBreak = ideographic(prev);
        if (BREAKABLE.has(prev) || ideographicBreak || (cp === 0x28 && i + 1 < cps.length)) {
          breaks.push(evaluateBreak(i, x, target, breaks, penalty(prev, cp, ideographicBreak && hinted), false));
        }
      }
      if (!whitespace(cp)) x += advance(cp);
    });
    for (let b = evaluateBreak(cps.length, x, target, breaks, 0, true); b; b = b.prior) ends.unshift(b.index);
  }
  const lines = [];
  let start = 0;
  for (const end of [...ends, ...(ends.at(-1) < cps.length ? [cps.length] : [])]) {
    let [a, b] = [start, end];
    while (a < b && whitespace(cps[a])) a++;
    while (b > a && whitespace(cps[b - 1])) b--;
    lines.push(cps.slice(a, b));
    start = end;
  }
  return lines;
}
