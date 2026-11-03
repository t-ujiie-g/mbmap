import assert from "node:assert/strict";
import test from "node:test";
import { buildSymbols, iconBox, iconCorners, LABEL_FLOATS, MAX_LABEL_CHARS, shapeIcon, SYMBOL_VERTEX_BYTES } from "./symbols.mjs";
import { SDF_BUFFER, SDF_SIZE } from "./text.mjs";

// A label's icon columns without an icon: no box, one layout, no indices.
const NO_ICON = [0, 0, 0, 0, 1, 0, 0];

// Every glyph a full em with ink, drawn by nothing (no OffscreenCanvas needed).
const glyphs = {
  metrics: () => ({ advance: SDF_SIZE, left: -SDF_BUFFER, top: SDF_SIZE * 0.88 + SDF_BUFFER, width: SDF_SIZE + 2 * SDF_BUFFER, height: SDF_SIZE + 2 * SDF_BUFFER }),
};

// A symbol entry as worker/labels.mbt writes it: centered, labels of (x, y,
// size, parts, sort key), the n-th label of feature 10 + n.
function entry(labels, vertical = 0, { justify = 2, anchors = [], placement = 0, spacing = 250, maxAngle = 45, icon = null } = {}) {
  const bytes = [];
  const u8 = (v) => bytes.push(v & 0xff);
  const u32 = (v) => [0, 8, 16, 24].forEach((s) => u8(v >>> s));
  const f64 = (v) => bytes.push(...new Uint8Array(new Float64Array([v]).buffer));
  const i16 = (v) => [0, 8].forEach((s) => u8(v >> s));
  [0, 0, 0, vertical].forEach(u8);
  [0, 0, 10, 1, 2].forEach(f64);
  u8(justify);
  u8(anchors.length);
  for (const [code, x, y] of anchors) {
    u8(code);
    f64(x);
    f64(y);
  }
  u8(placement);
  u8(1);
  f64(spacing);
  f64(maxAngle);
  u8(icon ? 1 : 0);
  if (icon) {
    [icon.anchor ?? 0, 0, 0, icon.optional ?? 0, icon.textOptional ?? 0, 0, 0, 0, icon.textFit ?? 0].forEach(u8);
    [...(icon.offset ?? [0, 0]), ...(icon.padding ?? [2, 2, 2, 2]), ...(icon.fitPadding ?? [0, 0, 0, 0])].forEach(f64);
  }
  u32(labels.length);
  const value = (p) => {
    if (typeof p === "number") {
      u8(3);
      f64(p);
    } else if (p === null) {
      u8(0);
    } else {
      const s = new TextEncoder().encode(p);
      u8(4);
      u32(s.length);
      bytes.push(...s);
    }
  };
  for (const [n, [x, y, size, parts, key = 0, lines = [], image = null]] of labels.entries()) {
    u32(10 + n);
    i16(x);
    i16(y);
    f64(size);
    f64(key);
    u32(parts.length);
    parts.forEach(value);
    if (icon) {
      u32(image ? 1 : 0);
      if (image) value(image[0]);
      f64(image?.[1] ?? 1);
      f64(image?.[2] ?? 0);
    }
    if (placement > 0) {
      u32(lines.length);
      for (const line of lines) {
        u32(line.length);
        for (const [px, py] of line) {
          i16(px);
          i16(py);
        }
      }
    }
  }
  return new Uint8Array(bytes);
}

test("labels become glyph quads with their anchors, offsets, glyph indices and boxes", () => {
  const s = buildSymbols(entry([[100, 200, 10, ["駅", 1]], [5, 6, 10, [null]]]), glyphs);
  // The second label has no text and is left out.
  assert.equal(s.labels.length, LABEL_FLOATS);
  assert.deepEqual([...s.labels], [100, 200, -10, -5, 10, 5, 10, 10, 0, ...NO_ICON, 1, 0, 12]);
  assert.deepEqual([...s.codepoints], ["駅".codePointAt(0), "1".codePointAt(0)]);
  assert.equal(s.vertices.byteLength, 2 * 4 * SYMBOL_VERTEX_BYTES);
  assert.equal(s.count, 12);
  const v = new DataView(s.vertices);
  const vertex = (n) => [0, 2, 4, 6, 8, 10, 12].map((o) => (o < 8 ? v.getInt16 : v.getUint16).call(v, n * SYMBOL_VERTEX_BYTES + o, true));
  // The second glyph's third corner: glyph 1, corner 2, size 10 px in 1/16 px.
  const pad = Math.round(((SDF_BUFFER * 10) / SDF_SIZE) * 4);
  assert.deepEqual(vertex(6), [100, 200, 40 + pad, 20 + pad, 1, 2, 160]);
  assert.deepEqual([...new Uint16Array(s.indices)].slice(0, 6), [0, 1, 2, 0, 2, 3]);
});

test("long labels are cut and far corners clamp to the i16 range", () => {
  const s = buildSymbols(entry([[0, 0, 400, ["x".repeat(MAX_LABEL_CHARS * 2)]]]), glyphs);
  assert.equal(s.count / 6, MAX_LABEL_CHARS);
  const v = new DataView(s.vertices);
  const xs = [];
  for (let o = 0; o < s.vertices.byteLength; o += SYMBOL_VERTEX_BYTES) xs.push(v.getInt16(o + 4, true));
  assert.equal(Math.min(...xs), -32768);
  assert.equal(Math.max(...xs), 32767);
});

test("lower sort keys come first", () => {
  const s = buildSymbols(entry([[1, 0, 10, ["a"], 5], [2, 0, 10, ["b"], -1], [3, 0, 10, ["c"], 5]]), glyphs);
  assert.deepEqual([0, 1, 2].map((i) => s.labels[i * LABEL_FLOATS]), [2, 1, 3]);
});

test("variable anchors: a multi-line label once per justification, a single line once", () => {
  const anchors = [[3, 0, 0.5], [1, 0.25, 0]];
  const s = buildSymbols(entry([[0, 0, 10, ["ab\nc"]], [1, 0, 10, ["ab"]]], 0, { justify: 0, anchors }), glyphs);
  assert.deepEqual([...s.anchors], anchors.flat());
  assert.equal(s.justify, 0);
  const row = (i) => [...s.labels.slice(i * LABEL_FLOATS, (i + 1) * LABEL_FLOATS)];
  // Centered boxes; three variants of 3 quads, then one of 2.
  assert.deepEqual(row(0), [0, 0, -10, -10, 10, 10, 10, 10, 0, ...NO_ICON, 3, 0, 18]);
  assert.deepEqual(row(1), [1, 0, -10, -5, 10, 5, 11, 10, 0, ...NO_ICON, 1, 54, 12]);
  assert.equal(s.count, (9 + 2) * 6);
  // "c" starts the second line at the left, the middle and the right.
  const v = new DataView(s.vertices);
  const left = (quad) => v.getInt16(quad * 4 * SYMBOL_VERTEX_BYTES + 4, true) / 4;
  const pad = (SDF_BUFFER * 10) / SDF_SIZE;
  assert.deepEqual([2, 5, 8].map(left), [-10 - pad, -5 - pad, 0 - pad]);
});

test("labels along lines: an instance per anchor and level, glyphs about their own middles", () => {
  const s = buildSymbols(entry([[0, 0, 10, ["ab"], 0, [[[50, 2048], [4000, 2048]]]]], 0, { placement: 2 }), glyphs);
  assert.equal(s.keepUpright, true);
  assert.deepEqual([...s.lines], [50, 2048, 4000, 2048]);
  assert.equal(s.labels.length, 3 * LABEL_FLOATS);
  assert.deepEqual([...s.labels.slice(0, 2)], [2025, 2048]);
  // Levels 0 to 2, each on segment 0 of the one line, glyphs 2 apart, circles 10 px wide.
  assert.deepEqual([...s.lineLabels], [0, 0, 0, 2, 0, 10, 1, 0, 0, 2, 2, 10, 2, 0, 0, 2, 4, 10]);
  assert.deepEqual([...s.glyphOffsets], [-12, 12, -12, 12, -12, 12]);
  const v = new DataView(s.vertices);
  const pad = Math.round(((SDF_BUFFER * 10) / SDF_SIZE) * 4);
  assert.deepEqual([v.getInt16(0, true), v.getInt16(4, true), v.getInt16(SYMBOL_VERTEX_BYTES * 4 + 4, true)], [2025, -20 - pad, -20 - pad]);
});

test("icons are shaped against their anchor and offset, padded and turned for collisions", () => {
  const image = [20, 10, 2, false];
  const icon = { anchor: 7, offset: [1, 2], textFit: 0, fitPadding: [0, 0, 0, 0] };
  // 10 x 5 px at size 1, its bottom-left corner at the offset.
  assert.deepEqual(shapeIcon(image, icon, null), [1, -3, 11, 2]);
  // Fit to a text box of (-20, -6)-(20, 6): stretched both ways with the padding, then centered on it.
  const fit = { ...icon, textFit: 3, fitPadding: [1, 2, 3, 4] };
  assert.deepEqual(shapeIcon(image, fit, [-20, -6, 20, 6]), [-23, -5, 23, 11]);
  assert.deepEqual(shapeIcon(image, { ...fit, textFit: 1 }, [-20, -6, 20, 6]), [-23, -0.5, 23, 4.5]);
  assert.deepEqual(iconBox([0, 0, 10, 4], 2, [1, 2, 3, 4], 0), [-4, -1, 22, 11]);
  const turned = iconBox([-1, -1, 1, 1], 1, [0, 0, 0, 0], 90).map((v) => Math.round(v * 1e9) / 1e9);
  assert.deepEqual(turned, [-1, -1, 1, 1]);
  // A quad a pixel of the image wider each side: 10 px over 20 image pixels.
  assert.deepEqual(iconCorners([0, 0, 10, 5], image, 0), [[-0.5, -0.5], [10.5, -0.5], [10.5, 5.5], [-0.5, 5.5]]);
});

test("labels with icons get an icon quad, its box and its image; missing images are listed", () => {
  const images = new Map([["dot", [8, 8, 1, false]]]);
  const s = buildSymbols(entry([[10, 20, 10, ["a"], 0, [], ["dot", 2, 0]], [30, 40, 10, [], 0, [], ["none", 1, 0]], [50, 60, 10, [], 0, [], ["dot", 1, 0]]], 0, { icon: {} }), glyphs, images);
  // The second label has neither text nor an image and is left out.
  assert.equal(s.labels.length, 2 * LABEL_FLOATS);
  assert.deepEqual(s.missing, ["none"]);
  assert.deepEqual(s.icon.images, ["dot"]);
  assert.equal(s.icon.count, 12);
  // Boxes at the layout size, padded by 2: 16 px, then 8 px.
  assert.deepEqual([...s.labels.slice(9, 16)], [-10, -10, 10, 10, 1, 0, 6]);
  assert.deepEqual([...s.labels.slice(LABEL_FLOATS + 9, LABEL_FLOATS + 16)], [-6, -6, 6, 6, 1, 6, 6]);
  // The icon-only label has no text indices.
  assert.equal(s.labels[2 * LABEL_FLOATS - 1], 0);
  const v = new DataView(s.icon.vertices);
  // The first quad's top-left corner at size 1 (-5 px in 32nds), image 0, size 2 x 128.
  assert.deepEqual([0, 2, 4, 6].map((o) => v.getInt16(o, true)), [10, 20, -160, -160]);
  assert.deepEqual([8, 10, 12].map((o) => v.getUint16(o, true)), [0, 0, 256]);
});

test("icons along lines go with each instance; alone they keep no distance from their like", () => {
  const images = new Map([["dot", [8, 8, 1, false]]]);
  const line = [[[50, 2048], [4000, 2048]]];
  const s = buildSymbols(entry([[0, 0, 10, [], 0, line, ["dot", 1, 0]], [0, 0, 10, [], 0, line, ["dot", 1, 0]]], 0, { placement: 2, icon: {} }), glyphs, images);
  // Two features at the line's middle, three levels each, none with text.
  assert.equal(s.labels.length, 6 * LABEL_FLOATS);
  assert.equal(s.icon.count, 6 * 6);
  const firsts = [0, 1, 2, 3, 4, 5].map((i) => s.labels[i * LABEL_FLOATS + 14]);
  assert.deepEqual([...firsts].sort((a, b) => a - b), [0, 6, 12, 18, 24, 30]);
  assert.equal(s.labels[LABEL_FLOATS - 1], 0);
});
