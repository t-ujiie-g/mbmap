// Symbol layer entries: labels from the wasm (docs/FORMATS.md, "Labels") laid
// out into glyph quads, with SDF glyphs drawn here by TinySDF.
import TinySDF from "./tiny-sdf.mjs";
import { JUSTIFY, layoutLabel, SDF_BUFFER, SDF_RADIUS, SDF_SIZE } from "./text.mjs";
import { EXTENT, lineAnchors, mergeLines } from "./line-labels.mjs";
import { readValue } from "./values.mjs";

// Bytes per glyph quad vertex (docs/FORMATS.md, "Symbol vertices").
export const SYMBOL_VERTEX_BYTES = 16;
// Floats per label in an entry's `labels`; mirrored as LABEL_FLOATS in map/labels.mbt.
export const LABEL_FLOATS = 12;
// Byte offsets in a symbol entry's header (worker/labels.mbt `Labels::bytes`);
// `anchors` (a count, then per anchor its code and offset) ends the fixed part.
const HEADER = { anchor: 0, allowOverlap: 1, ignorePlacement: 2, vertical: 3, offset: 4, maxWidth: 20, lineHeight: 28, padding: 36, justify: 44, anchors: 45 };
const ANCHOR_BYTES = 17;
// Justifications of a multi-line label with variable anchors and `text-justify: auto`.
const VARIANTS = ["left", "center", "right"];
// `symbol-placement` in worker/labels.mbt's codes.
const PLACEMENTS = ["point", "line", "line-center"];
// Labels along lines are found for tiles 1, 2 and 4 times as deep as the source's,
// as MapLibre lays them out again past its maxzoom; deeper zooms take the last.
export const LINE_LEVELS = 3;
// Most labels along lines one entry keeps, all levels together: a small `symbol-spacing`
// over long lines would make them without bound (AGENTS.md §8.2).
export const MAX_LINE_LABELS = 4096;
// Floats per label in an entry's `lineLabels`; mirrored as LINE_FLOATS in map/line_labels.mbt.
export const LINE_FLOATS = 6;
// MapLibre's tile units per `@core.TILE_EXTENT` unit (4096).
const TO_EXTENT = EXTENT / 4096;
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
    justify: JUSTIFY[view.getUint8(HEADER.justify)] ?? "center",
  };
  const tries = view.getUint8(HEADER.anchors);
  const anchors = new Float64Array(tries * 3);
  for (let k = 0; k < tries; k++) {
    const o = HEADER.anchors + 1 + k * ANCHOR_BYTES;
    anchors.set([view.getUint8(o), view.getFloat64(o + 1, true), view.getFloat64(o + 9, true)], k * 3);
  }
  const flags = {
    allowOverlap: view.getUint8(HEADER.allowOverlap) === 1,
    ignorePlacement: view.getUint8(HEADER.ignorePlacement) === 1,
    padding: view.getFloat64(HEADER.padding, true),
    anchors,
    justify: view.getUint8(HEADER.justify),
  };
  let at = HEADER.anchors + 1 + tries * ANCHOR_BYTES;
  const along = {
    placement: PLACEMENTS[view.getUint8(at)] ?? "point",
    keepUpright: view.getUint8(at + 1) === 1,
    spacing: view.getFloat64(at + 2, true),
    maxAngle: view.getFloat64(at + 10, true),
  };
  at += 18;
  const onLines = along.placement !== "point";
  // Along lines MapLibre shapes one centered line of text, whatever the layout says.
  const shaping = onLines ? { ...layout, maxWidth: Infinity, justify: "center", offset: [0, 0] } : layout;
  const count = view.getUint32(at, true);
  at += 4;
  let placed = [];
  const local = new Map();
  let quads = 0;
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
    const metrics = (cp) => glyphs.metrics(cp);
    let lines = null;
    if (onLines) [lines, at] = readLines(view, at);
    const shaped = layoutLabel(text, Math.min(size, 256), shaping, metrics);
    if (shaped.quads.length === 0) continue;
    if (onLines) {
      placed.push({ feature, size, key, text, shaped, lines });
      continue;
    }
    // With variable anchors a multi-line label is laid out once per justification
    // its anchors may take (MapLibre's `getAnchorJustification`), all centered.
    const variants = tries > 0 && layout.justify === "auto" && !layout.vertical && shaped.lines > 1
      ? VARIANTS.map((justify) => layoutLabel(text, Math.min(size, 256), { ...layout, justify }, metrics))
      : [shaped];
    placed.push({ feature, x, y, size, key, box: shaped.box, variants });
  }
  if (along.placement === "line") placed = mergeLines(placed);
  // Lower sort keys are placed (and drawn) first; ties keep their order.
  placed.sort((a, b) => a.key - b.key);
  const line = onLines ? alongLines(placed, along, layout.lineHeight) : null;
  if (line) placed = line.placed;
  for (const l of placed) {
    for (const q of l.variants[0].quads) if (!local.has(q.cp)) local.set(q.cp, local.size);
    l.first = quads;
    quads += l.variants[0].quads.length * l.variants.length;
  }
  const vertices = new ArrayBuffer(quads * 4 * SYMBOL_VERTEX_BYTES);
  const v = new DataView(vertices);
  const wide = quads * 4 > 65536;
  const indices = wide ? new Uint32Array(quads * 6) : new Uint16Array(quads * 6);
  const labels = new Float32Array(placed.length * LABEL_FLOATS);
  placed.forEach((l, i) => {
    const per = l.variants[0].quads.length;
    labels.set([l.x, l.y, ...l.box, l.feature, Math.min(l.size, 256), l.key, l.variants.length, l.first * 6, per * 6], i * LABEL_FLOATS);
    l.variants.flatMap((s) => s.quads).forEach((q, k) => {
      const n = l.first + k;
      // Along lines a glyph's corners are relative to its own middle.
      const dx = onLines ? q.along : 0;
      q.corners.forEach(([cx, cy], c) => {
        const o = (n * 4 + c) * SYMBOL_VERTEX_BYTES;
        v.setInt16(o, Math.round(l.x), true);
        v.setInt16(o + 2, Math.round(l.y), true);
        v.setInt16(o + 4, quarterPixels(cx - dx), true);
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
    ...(line ? { lineLabels: line.meta, lines: line.lines, glyphOffsets: line.glyphs, keepUpright: along.keepUpright } : {}),
  };
}

// Reads a label's lines (worker/labels.mbt `Labels::lines`) into MapLibre's tile units.
function readLines(view, at) {
  const lines = [];
  const n = view.getUint32(at, true);
  at += 4;
  for (let r = 0; r < n; r++) {
    const points = view.getUint32(at, true);
    at += 4;
    const line = [];
    for (let p = 0; p < points; p++, at += 4) {
      line.push({ x: view.getInt16(at, true) * TO_EXTENT, y: view.getInt16(at + 2, true) * TO_EXTENT });
    }
    lines.push(line);
  }
  return [lines, at];
}

// The labels along lines of `features` (sorted by key): an instance per anchor at each
// overscaling level, with the line it lies on (`lines`, x and y in `TILE_EXTENT` units),
// its glyphs' offsets along it (`glyphs`, glyph units) and `meta` (LINE_FLOATS per label).
function alongLines(features, along, lineHeight) {
  const placed = [];
  const lines = [];
  const glyphs = [];
  const meta = [];
  const starts = new Map();
  for (let level = 0; level < LINE_LEVELS; level++) {
    const seen = new Map();
    for (const f of features) {
      const size = Math.min(f.size, 256);
      const length = ((f.shaped.box[2] - f.shaped.box[0]) * 24) / size;
      for (const { anchor, line } of lineAnchors(f.lines, f.text, length, { ...along, size }, 2 ** level, seen, MAX_LINE_LABELS - placed.length)) {
        if (placed.length >= MAX_LINE_LABELS) break;
        if (!starts.has(line)) {
          starts.set(line, lines.length / 2);
          for (const p of line) lines.push(p.x / TO_EXTENT, p.y / TO_EXTENT);
        }
        const diameter = (Math.max(10, lineHeight * 24) * size) / 24;
        meta.push(level, anchor.segment, starts.get(line), line.length, glyphs.length, diameter);
        for (const q of f.shaped.quads) glyphs.push((q.along * 24) / size);
        const r = diameter / 2;
        placed.push({ ...f, x: anchor.x / TO_EXTENT, y: anchor.y / TO_EXTENT, box: [-r, -r, r, r], variants: [f.shaped], meta: meta.length / LINE_FLOATS - 1 });
      }
    }
  }
  // Sorted by key again across levels, rows and `meta` stay in step.
  const order = placed.map((_, i) => i).sort((a, b) => placed[a].key - placed[b].key);
  const sortedMeta = order.flatMap((i) => meta.slice(placed[i].meta * LINE_FLOATS, (placed[i].meta + 1) * LINE_FLOATS));
  return {
    placed: order.map((i) => placed[i]),
    meta: new Float32Array(sortedMeta),
    lines: new Float32Array(lines),
    glyphs: new Float32Array(glyphs),
  };
}
