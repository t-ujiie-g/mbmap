// Text layout of point labels, in CSS pixels relative to the anchor (y down).
// Import-free so tests run it as is.

// Glyph metrics come from TinySDF drawn at SDF_SIZE px with SDF_BUFFER px of
// padding around each bitmap.
export const SDF_SIZE = 48;
export const SDF_BUFFER = 6;
export const SDF_RADIUS = 16;

// `@style.TextAnchor` order (worker/labels.mbt `anchor_code`).
const ANCHORS = ["center", "left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right"];

// Japanese line-breaking rules (kinsoku): no break before closing marks and
// small kana, none after opening brackets.
const NO_BREAK_BEFORE = new Set([..."、。，．）」』】〉》〕｝！？ー・：；ぁぃぅぇぉっゃゅょァィゥェォッャュョ"]);
const NO_BREAK_AFTER = new Set([..."（「『【〈《〔｛"]);
const ideographic = (cp) => cp >= 0x2e80;

/**
 * Lays `text` out at `size` px, anchored and justified like MapLibre; `metrics(cp)`
 * gives {advance, left, top, width, height} at SDF_SIZE. Returns glyph quads and the text box.
 */
export function layoutLabel(text, size, { anchor = 0, offset = [0, 0], maxWidth = 10, lineHeight = 1.2 }, metrics) {
  const scale = size / SDF_SIZE;
  const lines = breakLines([...text].map((c) => c.codePointAt(0)), maxWidth * size, (cp) => metrics(cp).advance * scale);
  const widths = lines.map((l) => l.reduce((w, cp) => w + metrics(cp).advance * scale, 0));
  const width = Math.max(0, ...widths);
  const height = lines.length * lineHeight * size;
  const name = ANCHORS[anchor] ?? "center";
  const ax = name.endsWith("left") ? 0 : name.endsWith("right") ? -width : -width / 2;
  const ay = name.startsWith("top") ? 0 : name.startsWith("bottom") ? -height : -height / 2;
  const x0 = ax + offset[0] * size;
  const y0 = ay + offset[1] * size;
  const justify = name.endsWith("left") ? 0 : name.endsWith("right") ? 1 : 0.5;
  const quads = [];
  lines.forEach((line, i) => {
    let pen = x0 + (width - widths[i]) * justify;
    // The em box sits in the middle of the line box; 0.88 em of it above the baseline.
    const baseline = y0 + i * lineHeight * size + (lineHeight - 1) * size / 2 + 0.88 * size;
    for (const cp of line) {
      const m = metrics(cp);
      if (m.width > 2 * SDF_BUFFER && m.height > 2 * SDF_BUFFER) {
        const qx = pen + m.left * scale;
        const qy = baseline - m.top * scale;
        quads.push({ cp, x0: qx, y0: qy, x1: qx + m.width * scale, y1: qy + m.height * scale });
      }
      pen += m.advance * scale;
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
  return lines.map((l) => (l[l.length - 1] === 32 ? l.slice(0, -1) : l)).filter((l, i, all) => l.length > 0 || all.length === 1);
}
