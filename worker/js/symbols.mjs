// Symbol layer entries: labels from the wasm (docs/FORMATS.md, "Labels") laid
// out into glyph quads, with SDF glyphs drawn here by TinySDF.
import TinySDF from "./tiny-sdf.mjs";
import { layoutLabel, SDF_BUFFER, SDF_RADIUS, SDF_SIZE } from "./text.mjs";
import { readValue } from "./values.mjs";

// Bytes per glyph quad vertex (docs/FORMATS.md, "Symbol vertices").
export const SYMBOL_VERTEX_BYTES = 16;
// Floats per label in an entry's `labels`; mirrored as LABEL_FLOATS in map/labels.mbt.
export const LABEL_FLOATS = 9;
// Byte offsets in a symbol entry's header (worker/labels.mbt `Labels::bytes`).
const HEADER = { anchor: 0, allowOverlap: 1, ignorePlacement: 2, vertical: 3, offset: 4, maxWidth: 20, lineHeight: 28, padding: 36, count: 44, labels: 48 };
// Longest label kept, in characters: tile text is untrusted (AGENTS.md §8.2).
export const MAX_LABEL_CHARS = 256;
// Most glyphs a worker keeps, and draws for one tile; past them characters are
// left blank, so a tile cannot make it draw without bound.
export const MAX_GLYPHS = 4096;
export const MAX_NEW_GLYPHS_PER_TILE = 1024;
const BLANK = { advance: SDF_SIZE / 2, left: 0, top: 0, width: 0, height: 0 };


// SDF glyphs of one font, drawn once per worker; `fresh` lists the ones the
// main thread has not been sent yet.
export class Glyphs {
  constructor(fontFamily) {
    this.fontFamily = fontFamily;
    this.sdf = null;
    this.cache = new Map();
    this.fresh = new Set();
    this.budget = MAX_NEW_GLYPHS_PER_TILE;
  }

  // Starts a tile's allowance of new glyphs.
  startTile() {
    this.budget = MAX_NEW_GLYPHS_PER_TILE;
  }

  metrics(cp) {
    let g = this.cache.get(cp);
    if (!g) {
      if (this.cache.size >= MAX_GLYPHS || this.budget <= 0) return BLANK;
      this.budget--;
      this.sdf ??= new TinySDF({ fontSize: SDF_SIZE, buffer: SDF_BUFFER, radius: SDF_RADIUS, cutoff: 0.25, fontFamily: this.fontFamily });
      const d = this.sdf.draw(String.fromCodePoint(cp));
      g = { advance: d.glyphAdvance, left: d.glyphLeft - SDF_BUFFER, top: d.glyphTop + SDF_BUFFER, width: d.width, height: d.height, data: d.data };
      this.cache.set(cp, g);
      this.fresh.add(cp);
    }
    return g;
  }

  // The glyphs drawn since the last call, as transferable bitmaps.
  take() {
    const out = [];
    for (const cp of this.fresh) {
      const g = this.cache.get(cp);
      out.push({ cp, width: g.width, height: g.height, data: new Uint8Array(g.data.buffer.slice(0)) });
    }
    this.fresh.clear();
    return out;
  }
}

// setInt16 wraps around, so offsets past its range are clamped.
const quarterPixels = (px) => Math.max(-32768, Math.min(32767, Math.round(px * 4)));

// A label's text parts joined: null and absent parts are empty, numbers and
// booleans as JS writes them.
function readText(view, bytes, at, parts) {
  let text = "";
  for (let p = 0; p < parts; p++) {
    let v;
    [v, at] = readValue(view, bytes, at);
    if (v != null) text += String(v);
  }
  return [text, at];
}

// One symbol entry: `bytes` are its labels; returns the entry's buffers.
export function buildSymbols(bytes, glyphs) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const layout = {
    anchor: view.getUint8(HEADER.anchor),
    offset: [view.getFloat64(HEADER.offset, true), view.getFloat64(HEADER.offset + 8, true)],
    maxWidth: view.getFloat64(HEADER.maxWidth, true),
    lineHeight: view.getFloat64(HEADER.lineHeight, true),
    vertical: view.getUint8(HEADER.vertical) === 1,
  };
  const flags = {
    allowOverlap: view.getUint8(HEADER.allowOverlap) === 1,
    ignorePlacement: view.getUint8(HEADER.ignorePlacement) === 1,
    padding: view.getFloat64(HEADER.padding, true),
  };
  const count = view.getUint32(HEADER.count, true);
  const placed = [];
  const local = new Map();
  let quads = 0;
  let at = HEADER.labels;
  for (let i = 0; i < count; i++) {
    const feature = view.getUint32(at, true);
    const x = view.getInt16(at + 4, true);
    const y = view.getInt16(at + 6, true);
    const size = view.getFloat64(at + 8, true);
    const key = view.getFloat64(at + 16, true);
    const parts = view.getUint32(at + 24, true);
    let text;
    [text, at] = readText(view, bytes, at + 28, parts);
    const chars = [...text];
    if (chars.length > MAX_LABEL_CHARS) text = chars.slice(0, MAX_LABEL_CHARS).join("");
    const shaped = layoutLabel(text, Math.min(size, 256), layout, (cp) => glyphs.metrics(cp));
    if (shaped.quads.length === 0) continue;
    placed.push({ feature, x, y, size, key, shaped });
  }
  // Lower sort keys are placed (and drawn) first; ties keep their order.
  placed.sort((a, b) => a.key - b.key);
  for (const l of placed) {
    for (const q of l.shaped.quads) if (!local.has(q.cp)) local.set(q.cp, local.size);
    l.first = quads;
    quads += l.shaped.quads.length;
  }
  const vertices = new ArrayBuffer(quads * 4 * SYMBOL_VERTEX_BYTES);
  const v = new DataView(vertices);
  const wide = quads * 4 > 65536;
  const indices = wide ? new Uint32Array(quads * 6) : new Uint16Array(quads * 6);
  const labels = new Float32Array(placed.length * LABEL_FLOATS);
  placed.forEach((l, i) => {
    labels.set([l.x, l.y, ...l.shaped.box, l.feature, l.first * 6, l.shaped.quads.length * 6], i * LABEL_FLOATS);
    l.shaped.quads.forEach((q, k) => {
      const n = l.first + k;
      q.corners.forEach(([cx, cy], c) => {
        const o = (n * 4 + c) * SYMBOL_VERTEX_BYTES;
        v.setInt16(o, l.x, true);
        v.setInt16(o + 2, l.y, true);
        v.setInt16(o + 4, quarterPixels(cx), true);
        v.setInt16(o + 6, quarterPixels(cy), true);
        v.setUint16(o + 8, local.get(q.cp), true);
        v.setUint16(o + 10, c, true);
        v.setUint16(o + 12, Math.round(l.size * 16), true);
      });
      indices.set([n * 4, n * 4 + 1, n * 4 + 2, n * 4, n * 4 + 2, n * 4 + 3], n * 6);
    });
  });
  return {
    vertices,
    indices: indices.buffer,
    count: indices.length,
    indexBytes: wide ? 4 : 2,
    labels,
    codepoints: Uint32Array.from(local.keys()),
    ...flags,
  };
}
