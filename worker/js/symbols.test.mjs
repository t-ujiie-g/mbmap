import assert from "node:assert/strict";
import test from "node:test";
import { buildSymbols, LABEL_FLOATS, MAX_LABEL_CHARS, SYMBOL_VERTEX_BYTES } from "./symbols.mjs";
import { SDF_BUFFER, SDF_SIZE } from "./text.mjs";

// Every glyph a full em with ink, drawn by nothing (no OffscreenCanvas needed).
const glyphs = {
  metrics: () => ({ advance: SDF_SIZE, left: -SDF_BUFFER, top: SDF_SIZE * 0.88 + SDF_BUFFER, width: SDF_SIZE + 2 * SDF_BUFFER, height: SDF_SIZE + 2 * SDF_BUFFER }),
};

// A symbol entry as worker/labels.mbt writes it: centered, labels of (x, y,
// size, parts, sort key).
function entry(labels, vertical = 0) {
  const bytes = [];
  const u8 = (v) => bytes.push(v & 0xff);
  const u32 = (v) => [0, 8, 16, 24].forEach((s) => u8(v >>> s));
  const f64 = (v) => bytes.push(...new Uint8Array(new Float64Array([v]).buffer));
  const i16 = (v) => [0, 8].forEach((s) => u8(v >> s));
  [0, 0, 0, vertical].forEach(u8);
  [0, 0, 10, 1, 2].forEach(f64);
  u32(labels.length);
  for (const [x, y, size, parts, key = 0] of labels) {
    i16(x);
    i16(y);
    f64(size);
    f64(key);
    u32(parts.length);
    for (const p of parts) {
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
    }
  }
  return new Uint8Array(bytes);
}

test("labels become glyph quads with their anchors, offsets, glyph indices and boxes", () => {
  const s = buildSymbols(entry([[100, 200, 10, ["駅", 1]], [5, 6, 10, [null]]]), glyphs);
  // The second label has no text and is left out.
  assert.equal(s.labels.length, LABEL_FLOATS);
  assert.deepEqual([...s.labels], [100, 200, -10, -5, 10, 5, 0, 12]);
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
