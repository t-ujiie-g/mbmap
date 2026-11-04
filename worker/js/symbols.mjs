// Symbol layer entries: labels from the wasm (docs/FORMATS.md, "Labels") laid
// out into glyph quads, with SDF glyphs drawn here by TinySDF.
import TinySDF from "./tiny-sdf.mjs";
import { anchorShares, JUSTIFY, layoutLabel, SDF_BUFFER, SDF_RADIUS, SDF_SIZE } from "./text.mjs";
import { EXTENT, lineAnchors, mergeLines } from "./line-labels.mjs";
import { readString, readValue } from "./values.mjs";

// Bytes per glyph quad vertex, and per vertex of `colors` (docs/FORMATS.md, "Symbol vertices").
export const SYMBOL_VERTEX_BYTES = 16;
const COLOR_BYTES = 8;
// Floats per label in an entry's `labels`; mirrored as LABEL_FLOATS in map/labels.mbt.
export const LABEL_FLOATS = 19;
// Where a label's icon columns start in its `labels` row: box (4), 1, first index, index count.
// Mirrored as ICON_COLUMN in map/labels.mbt.
export const ICON_COLUMN = 9;
// Icon sizes per vertex are packed as MapLibre's (`SIZE_PACK_FACTOR`), corner offsets in 32nds of
// a px; the symbol shader in render_webgl2/gl.mbt divides by both (`a_size / 128.0`, `a_data / 32.0`).
const SIZE_PACK = 128;
const OFFSET_PACK = 32;
// Byte offsets in a symbol entry's header (worker/labels.mbt `Labels::bytes`);
// `anchors` (a count, then per anchor its code and offset) ends the fixed part.
const HEADER = { anchor: 0, allowOverlap: 1, ignorePlacement: 2, vertical: 3, offset: 4, maxWidth: 20, lineHeight: 28, padding: 36, justify: 44, anchors: 45 };
// A variable anchor in that header: its code and two f64 offsets (worker/labels.mbt `Labels::bytes`).
const ANCHOR_BYTES = 17;
// Indices per glyph or icon quad (two triangles); mirrored as QUAD_INDICES in map/labels.mbt.
const QUAD_INDICES = 6;
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
// Most missing image names one entry reports.
const MAX_MISSING = 64;
export const MAX_NEW_GLYPHS_PER_TILE = 1024;
const BLANK = { advance: SDF_SIZE / 2, left: 0, top: 0, width: 0, height: 0 };


// Most fonts a worker draws glyphs with (worker/labels.mbt `MAX_FONTS`); past them the map's own.
const MAX_FONTS = 32;
// A glyph's key: its font's index in `faces` times this, plus its code point.
const FONT_KEY = 2 ** 21;

// SDF glyphs, drawn once per worker in the map's font (`fontFamily`) or a face of `text-font`
// (`faces`: style, weight and family lines, worker/labels.mbt `Labels::font`; "" the map's font);
// `fresh` lists the ones the main thread has not been sent yet.
export class Glyphs {
  constructor(fontFamily) {
    this.fontFamily = fontFamily;
    this.faces = [""];
    this.sdfs = [];
    this.cache = new Map();
    this.fresh = new Set();
    this.budget = MAX_NEW_GLYPHS_PER_TILE;
  }

  // Starts a tile's allowance of new glyphs.
  startTile() {
    this.budget = MAX_NEW_GLYPHS_PER_TILE;
  }

  // The index of a face, which then has the map's font after its families as MapLibre adds sans-serif.
  face(f) {
    let i = this.faces.indexOf(f);
    if (i < 0 && this.faces.length < MAX_FONTS) i = this.faces.push(f) - 1;
    return Math.max(i, 0);
  }

  metrics(cp, font = 0) {
    const key = font * FONT_KEY + cp;
    let g = this.cache.get(key);
    if (!g) {
      if (this.cache.size >= MAX_GLYPHS || this.budget <= 0) return BLANK;
      this.budget--;
      const [fontStyle, fontWeight, family] = this.faces[font].split("\n");
      this.sdfs[font] ??= new TinySDF({
        fontSize: SDF_SIZE, buffer: SDF_BUFFER, radius: SDF_RADIUS, cutoff: 0.25,
        fontFamily: family ? `${family},${this.fontFamily}` : this.fontFamily, fontWeight: fontWeight || undefined, fontStyle: fontStyle || undefined,
      });
      const d = this.sdfs[font].draw(String.fromCodePoint(cp));
      g = { key, advance: d.glyphAdvance, left: d.glyphLeft - SDF_BUFFER, top: d.glyphTop + SDF_BUFFER, width: d.width, height: d.height, data: d.data };
      this.cache.set(key, g);
      this.fresh.add(key);
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
const clamp16 = (v) => Math.max(-32768, Math.min(32767, Math.round(v)));
// Glyph corners are kept in 16ths of a CSS px (docs/FORMATS.md "Symbol vertices").
export const OFFSET_UNITS = 16;
const offsetUnits = (px) => clamp16(px * OFFSET_UNITS);

/**
 * MapLibre's `shapeIcon` and, with `icon-text-fit` (`fit` 1 width, 2 height, 3 both) around a text
 * `box` (CSS px), `fitIconToText`: the icon's left, top, right, bottom at size 1. `image` is
 * [width, height, pixelRatio, sdf].
 */
export function shapeIcon(image, icon, box) {
  const [w, h] = [image[0] / image[2], image[1] / image[2]];
  const [dx, dy] = icon.offset;
  const fit = box ? icon.textFit : 0;
  const [pt, pr, pb, pl] = icon.fitPadding;
  const [ha, va] = anchorShares(icon.anchor);
  let left = dx - w * ha;
  let top = dy - h * va;
  if (fit) left = fit & 1 ? dx + box[0] - pl : dx + (box[0] + box[2] - w) / 2;
  if (fit) top = fit & 2 ? dy + box[1] - pt : dy + (box[1] + box[3] - h) / 2;
  const right = fit & 1 ? dx + box[2] + pr : left + w;
  const bottom = fit & 2 ? dy + box[3] + pb : top + h;
  return [left, top, right, bottom];
}

const rotation = (degrees) => {
  const a = (degrees * Math.PI) / 180;
  return [Math.cos(a), Math.sin(a)];
};

/**
 * An icon's collision box in CSS px at `size` (MapLibre's `CollisionFeature`): padded, and the
 * envelope of its turn by `rotate` degrees.
 */
export function iconBox(shaped, size, padding, rotate) {
  const [pt, pr, pb, pl] = padding;
  const x1 = shaped[0] * size - pl, y1 = shaped[1] * size - pt, x2 = shaped[2] * size + pr, y2 = shaped[3] * size + pb;
  if (!rotate) return [x1, y1, x2, y2];
  const [c, s] = rotation(rotate);
  const xs = [], ys = [];
  for (const [x, y] of [[x1, y1], [x2, y1], [x1, y2], [x2, y2]]) {
    xs.push(c * x - s * y);
    ys.push(s * x + c * y);
  }
  return [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)];
}

/**
 * The corners (top-left, top-right, bottom-right, bottom-left) of an icon's quad at size 1, a pixel
 * of the image wider on each side (MapLibre's `getIconQuads`), turned by `rotate` degrees.
 */
export function iconCorners(shaped, image, rotate) {
  const [left, top, right, bottom] = shaped;
  const bx = (right - left) / image[0], by = (bottom - top) / image[1];
  const [c, s] = rotation(rotate);
  return [[left - bx, top - by], [right + bx, top - by], [right + bx, bottom + by], [left - bx, bottom + by]]
    .map(([x, y]) => [c * x - s * y, s * x + c * y]);
}

// A formatted text's sections among a label's parts (worker/labels.mbt `LABEL_SECTIONS`).
const SECTIONS = 6;
// Font scales a glyph may take: its size per vertex is a u16 of 16ths of a px.
const MAX_FONT_SCALE = 15;

// Code points of the scripts whose letters join, which MapLibre never spaces apart (a part of its
// `codePointIsInCursiveScript`).
const CURSIVE = /[\u0600-\u08ff\u1800-\u18af\ua840-\ua877\ufb50-\ufdff\ufe70-\ufeff]/;

// A label's text parts joined in `transform`'s case (1 upper, 2 lower; null and absent parts empty, numbers
// and booleans as JS writes them). With a formatted part, also each code point's font scale, vertical-align
// code, font (an index into the entry's, 255 for the label's) and color.
function readText(view, bytes, at, parts, skip = 0, transform = 0) {
  at += skip;
  let text = "";
  let sections = null;
  const scales = [];
  const aligns = [];
  const fonts = [];
  const colors = [];
  const add = (s, scale = 1, align = 0, font = 255, color = null) => {
    s = transform === 1 ? s.toLocaleUpperCase() : transform === 2 ? s.toLocaleLowerCase() : s;
    for (const _ of s) {
      scales.push(scale);
      aligns.push(align);
      fonts.push(font);
      colors.push(color);
    }
    text += s;
  };
  for (let p = 0; p < parts; p++) {
    if (view.getUint8(at) === SECTIONS) {
      const n = view.getUint32(at + 1, true);
      at += 5;
      sections = { scales, aligns, fonts, colors };
      for (let k = 0; k < n; k++) {
        let s;
        [s, at] = readString(view, bytes, at);
        const scale = view.getFloat64(at, true);
        const colored = view.getUint8(at + 10) === 1;
        add(s, Math.max(0, Math.min(scale || 1, MAX_FONT_SCALE)), view.getUint8(at + 8), view.getUint8(at + 9), colored ? bytes.slice(at + 11, at + 15) : null);
        at += colored ? 15 : 11;
      }
      continue;
    }
    let v;
    [v, at] = readValue(view, bytes, at);
    if (v != null) add(String(v));
  }
  return [text, at, sections];
}

// One symbol entry: `bytes` are its labels, `images` the style's images by name
// ([width, height, pixelRatio, sdf]); returns the entry's buffers.
export function buildSymbols(bytes, glyphs, images = new Map()) {
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
  let icon = null;
  if (view.getUint8(at++) === 1) {
    const flag = (k) => view.getUint8(at + k) === 1;
    const f64 = (k) => view.getFloat64(at + 9 + k * 8, true);
    icon = {
      anchor: view.getUint8(at), allowOverlap: flag(1), ignorePlacement: flag(2), optional: flag(3), textOptional: flag(4),
      rotateWithMap: flag(5), pitchWithMap: flag(6), keepUpright: flag(7), textFit: view.getUint8(at + 8),
      offset: [f64(0), f64(1)], padding: [f64(2), f64(3), f64(4), f64(5)], fitPadding: [f64(6), f64(7), f64(8), f64(9)],
    };
    at += 89;
  }
  const onLines = along.placement !== "point";
  const faces = [];
  for (let n = view.getUint8(at++), f; faces.length < n; faces.push(glyphs.face(f))) [f, at] = readString(view, bytes, at);
  const count = view.getUint32(at, true);
  at += 4;
  let placed = [];
  const missing = new Set();
  const local = new Map();
  let quads = 0;
  for (let i = 0; i < count; i++) {
    const feature = view.getUint32(at, true);
    const x = view.getInt16(at + 4, true);
    const y = view.getInt16(at + 6, true);
    const size = view.getFloat64(at + 8, true);
    const key = view.getFloat64(at + 16, true);
    const font = faces[view.getUint8(at + 24) - 1] ?? 0;
    const spacing = view.getFloat64(at + 26, true);
    const rotate = view.getFloat64(at + 34, true);
    let text, sections;
    [text, at, sections] = readText(view, bytes, at + 46, view.getUint32(at + 42, true), 0, view.getUint8(at + 25));
    const chars = [...text];
    if (chars.length > MAX_LABEL_CHARS) text = chars.slice(0, MAX_LABEL_CHARS).join("");
    const metrics = (cp, k) => glyphs.metrics(cp, sections?.fonts[k] < 255 ? faces[sections.fonts[k] - 1] ?? 0 : font);
    // Along lines MapLibre shapes one centered line of text, whatever the layout says.
    const shaping = { ...layout, spacing: CURSIVE.test(text) ? 0 : spacing, ...(onLines ? { maxWidth: Infinity, justify: "center", offset: [0, 0] } : {}) };
    let iconName = "";
    let iconSize = 1;
    let iconRotate = 0;
    if (icon) {
      [iconName, at] = readText(view, bytes, at, view.getUint32(at, true), 4);
      iconSize = view.getFloat64(at, true);
      iconRotate = view.getFloat64(at + 8, true);
      at += 16;
    }
    let lines = null;
    if (onLines) [lines, at] = readLines(view, at);
    const shaped = layoutLabel(text, Math.min(size, 256), shaping, metrics, sections);
    const image = iconName ? images.get(iconName) : undefined;
    // Names come from tiles: a few short ones are reported, as MapLibre reports each.
    if (iconName && !image && iconName.length <= MAX_LABEL_CHARS && missing.size < MAX_MISSING) missing.add(iconName);
    if (shaped.quads.length === 0 && !image) continue;
    const shapedIcon = image ? shapeIcon(image, icon, shaped.quads.length > 0 ? shaped.box : null) : null;
    // Sizes may come from tiles; past 511 they do not fit the vertex's u16.
    const scale = Math.max(0, Math.min(iconSize, 511));
    const iconRow = shapedIcon
      ? { name: iconName, image, size: scale, rotate: iconRotate, shaped: shapedIcon, box: iconBox(shapedIcon, scale, icon.padding, iconRotate) }
      : null;
    if (onLines) {
      placed.push({ feature, size, key, text: shaped.quads.length > 0 ? text : "", shaped, lines, icon: iconRow, rotate, sections });
      continue;
    }
    // With variable anchors a multi-line label is laid out once per justification
    // its anchors may take (MapLibre's `getAnchorJustification`), all centered.
    const variants = tries > 0 && layout.justify === "auto" && !layout.vertical && shaped.lines > 1
      ? VARIANTS.map((justify) => layoutLabel(text, Math.min(size, 256), { ...shaping, justify }, metrics, sections))
      : [shaped];
    // A turned text's collision box is the envelope of its padded box turned (MapLibre's
    // `CollisionFeature`), less the padding the main thread adds.
    const p = flags.padding;
    const box = rotate ? iconBox(shaped.box, 1, [p, p, p, p], rotate).map((v, k) => v + (k < 2 ? p : -p)) : shaped.box;
    placed.push({ feature, x, y, size, key, box, variants, icon: iconRow, rotate, sections });
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
  const colors = placed.some((l) => l.sections?.colors.some((c) => c)) ? new Uint8Array(quads * 4 * COLOR_BYTES) : null;
  const wide = quads * 4 > 65536;
  const indices = wide ? new Uint32Array(quads * QUAD_INDICES) : new Uint16Array(quads * QUAD_INDICES);
  const labels = new Float32Array(placed.length * LABEL_FLOATS);
  const iconLabels = placed.filter((l) => l.icon);
  const icons = iconQuads(iconLabels);
  placed.forEach((l, i) => {
    const per = l.variants[0].quads.length;
    const ic = l.icon ? [...l.icon.box, 1, l.icon.index * QUAD_INDICES, QUAD_INDICES] : [0, 0, 0, 0, 1, 0, 0];
    labels.set([l.x, l.y, ...l.box, l.feature, Math.min(l.size, 256), l.key, ...ic, l.variants.length, l.first * QUAD_INDICES, per * QUAD_INDICES], i * LABEL_FLOATS);
    l.variants.flatMap((s) => s.quads).forEach((q, k) => {
      const n = l.first + k;
      // Along lines a glyph's corners are relative to its own middle, about which it turns.
      const dx = onLines ? q.along : 0;
      const [cos, sin] = rotation(l.rotate);
      const color = l.sections?.colors[q.k];
      q.corners.forEach(([cx, cy], c) => {
        const o = (n * 4 + c) * SYMBOL_VERTEX_BYTES;
        if (color) colors.set([...color, 1], (n * 4 + c) * COLOR_BYTES);
        v.setInt16(o, Math.round(l.x), true);
        v.setInt16(o + 2, Math.round(l.y), true);
        v.setInt16(o + 4, offsetUnits(cos * (cx - dx) - sin * cy), true);
        v.setInt16(o + 6, offsetUnits(sin * (cx - dx) + cos * cy), true);
        v.setUint16(o + 8, local.get(q.cp), true);
        v.setUint16(o + 10, c, true);
        v.setUint16(o + 12, Math.min(65535, Math.round(l.size * 16)), true);
      });
      indices.set([n * 4, n * 4 + 1, n * 4 + 2, n * 4, n * 4 + 2, n * 4 + 3], n * QUAD_INDICES);
    });
  });
  return {
    vertices,
    ...(colors ? { colors: colors.buffer } : {}),
    indices: indices.buffer,
    count: indices.length,
    indexBytes: wide ? 4 : 2,
    labels,
    codepoints: Uint32Array.from(local.keys()),
    ...flags,
    ...(icon ? { icon: { ...icon, ...icons, hasOffset: icon.offset[0] !== 0 || icon.offset[1] !== 0 }, missing: [...missing] } : {}),
    ...(line ? { lineLabels: line.meta, lines: line.lines, glyphOffsets: line.glyphs, keepUpright: along.keepUpright } : {}),
  };
}

// The icons of `labels`, one quad each (docs/FORMATS.md "Symbol vertices": corners in
// OFFSET_PACK-ths of a px at size 1, sizes times SIZE_PACK); `sdf` as the first icon's (MapLibre's
// `sdfIcons`), `rotated` if any icon is turned.
function iconQuads(labels) {
  const names = new Map();
  const vertices = new ArrayBuffer(labels.length * 4 * SYMBOL_VERTEX_BYTES);
  const v = new DataView(vertices);
  const wide = labels.length * 4 > 65536;
  const indices = wide ? new Uint32Array(labels.length * QUAD_INDICES) : new Uint16Array(labels.length * QUAD_INDICES);
  labels.forEach((l, n) => {
    const { name, image, size, rotate, shaped } = l.icon;
    l.icon.index = n;
    if (!names.has(name)) names.set(name, names.size);
    iconCorners(shaped, image, rotate).forEach(([cx, cy], c) => {
      const o = (n * 4 + c) * SYMBOL_VERTEX_BYTES;
      v.setInt16(o, Math.round(l.x), true);
      v.setInt16(o + 2, Math.round(l.y), true);
      v.setInt16(o + 4, clamp16(cx * OFFSET_PACK), true);
      v.setInt16(o + 6, clamp16(cy * OFFSET_PACK), true);
      v.setUint16(o + 8, names.get(name), true);
      v.setUint16(o + 10, c, true);
      v.setUint16(o + 12, Math.round(size * SIZE_PACK), true);
    });
    indices.set([n * 4, n * 4 + 1, n * 4 + 2, n * 4, n * 4 + 2, n * 4 + 3], n * QUAD_INDICES);
  });
  return {
    vertices,
    indices: indices.buffer,
    count: indices.length,
    indexBytes: wide ? 4 : 2,
    images: [...names.keys()],
    sdf: labels[0]?.icon.image[3] === true,
    rotated: labels.some((l) => l.icon.rotate !== 0),
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
      // MapLibre's `getShapedLabelLength`: the text's in glyph units or the icon's in px, the longer.
      const length = Math.max(f.text ? ((f.shaped.box[2] - f.shaped.box[0]) * 24) / size : 0, f.icon ? f.icon.shaped[2] - f.icon.shaped[0] : 0);
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
        placed.push({
          ...f, x: anchor.x / TO_EXTENT, y: anchor.y / TO_EXTENT, box: [-r, -r, r, r], variants: [f.shaped],
          meta: meta.length / LINE_FLOATS - 1, icon: f.icon && { ...f.icon },
        });
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
