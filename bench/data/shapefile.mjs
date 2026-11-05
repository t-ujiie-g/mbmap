// Shapefiles (ESRI's 1998 white paper: .shp, .shx, dBASE III .dbf) and zip archives
// (PKWARE's APPNOTE) written for the data goldens and the pack test's fixtures.
import { crc32, deflateRawSync } from "node:zlib";

// Shift_JIS bytes per character, from the host's decoder run over every two-byte code.
let sjis = null;
function sjisMap() {
  if (sjis) return sjis;
  sjis = new Map();
  const decoder = new TextDecoder("shift_jis");
  for (let lead = 0x81; lead <= 0xfc; lead++) {
    if (lead > 0x9f && lead < 0xe0) continue;
    for (let trail = 0x40; trail <= 0xfc; trail++) {
      if (trail === 0x7f) continue;
      const c = decoder.decode(Uint8Array.of(lead, trail));
      if (c.length === 1 && c !== "�" && !sjis.has(c)) sjis.set(c, [lead, trail]);
    }
  }
  for (let b = 0xa1; b <= 0xdf; b++) sjis.set(decoder.decode(Uint8Array.of(b)), [b]);
  return sjis;
}

/** `text` in `encoding` ("utf-8" or "shift_jis"). */
export function encodeText(text, encoding = "utf-8") {
  if (encoding === "utf-8") return new TextEncoder().encode(text);
  const map = sjisMap();
  const out = [];
  for (const c of text) {
    if (c.charCodeAt(0) < 0x80) out.push(c.charCodeAt(0));
    else if (map.has(c)) out.push(...map.get(c));
    else throw new Error(`no Shift_JIS for ${c}`);
  }
  return Uint8Array.from(out);
}

function append(to, ...arrays) {
  for (const a of arrays) for (const b of a) to.push(b);
}

class Writer {
  constructor() {
    this.bytes = [];
  }
  u8(...v) {
    this.bytes.push(...v);
  }
  i32(v, little = true) {
    const b = Buffer.alloc(4);
    little ? b.writeInt32LE(v) : b.writeInt32BE(v);
    this.bytes.push(...b);
  }
  u16(v) {
    const b = Buffer.alloc(2);
    b.writeUInt16LE(v);
    this.bytes.push(...b);
  }
  f64(v) {
    const b = Buffer.alloc(8);
    b.writeDoubleLE(v);
    this.bytes.push(...b);
  }
  get length() {
    return this.bytes.length;
  }
  done() {
    return Uint8Array.from(this.bytes);
  }
}

const range = (vs) => vs.reduce(([lo, hi], v) => [Math.min(lo, v), Math.max(hi, v)], [Infinity, -Infinity]);
function bboxOf(points) {
  const [x, y] = [range(points.map((p) => p[0])), range(points.map((p) => p[1]))];
  return [x[0], y[0], x[1], y[1]];
}

// A record's content: `parts` lists of [x, y] (one point for a Point), `type` the shape type;
// Z values are x + y, M values x - y.
function content(type, parts) {
  const w = new Writer();
  if (parts === null) {
    w.i32(0);
    return w.done();
  }
  w.i32(type);
  const base = type % 10;
  const z = type > 10 && type < 20;
  const m = type > 10;
  const points = parts.flat();
  if (base === 1) {
    w.f64(points[0][0]);
    w.f64(points[0][1]);
    if (z) w.f64(points[0][0] + points[0][1]);
    if (m) w.f64(points[0][0] - points[0][1]);
    return w.done();
  }
  bboxOf(points).forEach((v) => w.f64(v));
  if (base !== 8) w.i32(parts.length);
  w.i32(points.length);
  if (base !== 8) {
    let at = 0;
    for (const p of parts) {
      w.i32(at);
      at += p.length;
    }
  }
  for (const p of points) {
    w.f64(p[0]);
    w.f64(p[1]);
  }
  const extra = (f) => {
    const vs = points.map(f);
    range(vs).forEach((v) => w.f64(v));
    vs.forEach((v) => w.f64(v));
  };
  if (z) extra((p) => p[0] + p[1]);
  if (m) extra((p) => p[0] - p[1]);
  return w.done();
}

function header(type, words, points) {
  const w = new Writer();
  w.i32(9994, false);
  for (let i = 0; i < 5; i++) w.i32(0, false);
  w.i32(words, false);
  w.i32(1000);
  w.i32(type);
  const box = points.length ? bboxOf(points) : [0, 0, 0, 0];
  box.forEach((v) => w.f64(v));
  for (let i = 0; i < 4; i++) w.f64(0);
  return w.bytes;
}

/**
 * A shapefile of `records` ({ parts (lists of [x, y]; null for a null shape), values (by field),
 * deleted }) with shape `type` and `fields` ({ name, type: "C" | "N" | "F" | "L" | "D", length,
 * decimals }); text in `encoding`, `ldid` the .dbf's language driver id.
 */
export function writeShapefile(records, { type, fields = [], encoding = "utf-8", ldid = 0 }) {
  const shp = [];
  const shx = [];
  const contents = records.map((r) => content(type, r.parts));
  let offset = 50;
  contents.forEach((c, i) => {
    const w = new Writer();
    w.i32(i + 1, false);
    w.i32(c.length / 2, false);
    append(shp, w.bytes, c);
    const x = new Writer();
    x.i32(offset, false);
    x.i32(c.length / 2, false);
    append(shx, x.bytes);
    offset += 4 + c.length / 2;
  });
  const points = records.flatMap((r) => (r.parts ?? []).flat());
  const shpOut = Uint8Array.from([...header(type, 50 + shp.length / 2, points), ...shp]);
  const shxOut = Uint8Array.from([...header(type, 50 + shx.length / 2, points), ...shx]);
  const d = new Writer();
  const recLen = 1 + fields.reduce((s, f) => s + f.length, 0);
  d.u8(3, 124, 1, 1);
  d.i32(records.length);
  d.u16(32 + 32 * fields.length + 1);
  d.u16(recLen);
  for (let i = 12; i < 32; i++) d.u8(i === 29 ? ldid : 0);
  for (const f of fields) {
    const name = encodeText(f.name, encoding);
    for (let i = 0; i < 11; i++) d.u8(name[i] ?? 0);
    d.u8(f.type.charCodeAt(0), 0, 0, 0, 0, f.length, f.decimals ?? 0);
    for (let i = 0; i < 14; i++) d.u8(0);
  }
  d.u8(0x0d);
  for (const r of records) {
    d.u8(r.deleted ? 0x2a : 0x20);
    fields.forEach((f, i) => {
      const v = r.values?.[i];
      let text = v === null || v === undefined ? "" : String(v);
      if (f.type === "N" || f.type === "F") text = text.padStart(f.length);
      const bytes = encodeText(text, encoding).subarray(0, f.length);
      for (let k = 0; k < f.length; k++) d.u8(bytes[k] ?? 0x20);
    });
  }
  d.u8(0x1a);
  return { shp: shpOut, shx: shxOut, dbf: d.done() };
}

/**
 * A zip archive of `files` ({ name, data, method: 0 or 8 (default), flags, size and writtenMethod
 * (to lie about the inflated size or the method) }); names in UTF-8 with the flag set.
 */
export function writeZip(files) {
  const out = [];
  const central = [];
  for (const f of files) {
    const method = f.method ?? 8;
    const data = method === 8 ? new Uint8Array(deflateRawSync(f.data)) : f.data;
    const name = new TextEncoder().encode(f.name);
    const flags = (f.flags ?? 0) | 0x800;
    const fields = (w) => {
      w.u16(flags);
      w.u16(f.writtenMethod ?? method);
      w.u16(0);
      w.u16(0x21);
      w.i32(crc32(f.data) | 0);
      w.i32(data.length);
      w.i32(f.size ?? f.data.length);
      w.u16(name.length);
      w.u16(0);
    };
    const local = new Writer();
    local.i32(0x04034b50);
    local.u16(20);
    fields(local);
    const at = out.length;
    append(out, local.bytes, name, data);
    const c = new Writer();
    c.i32(0x02014b50);
    c.u16(20);
    c.u16(20);
    fields(c);
    c.u16(0);
    c.u16(0);
    c.u16(0);
    c.i32(0);
    c.i32(at);
    append(central, c.bytes, name);
  }
  const e = new Writer();
  e.i32(0x06054b50);
  e.u16(0);
  e.u16(0);
  e.u16(files.length);
  e.u16(files.length);
  e.i32(central.length);
  e.i32(out.length);
  e.u16(0);
  return Uint8Array.from([...out, ...central, ...e.bytes]);
}
