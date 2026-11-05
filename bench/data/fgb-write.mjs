// A FlatGeobuf writer for bench/data/fgb-golden.mjs and pack-fixtures.mjs: any column type, an
// index of any node size, a CRS; geometries by flatgeobuf 4.6.1's own builder.
import * as flatbuffers from "flatbuffers";
import { Column } from "flatgeobuf/lib/mjs/flat-geobuf/column.js";
import { Crs } from "flatgeobuf/lib/mjs/flat-geobuf/crs.js";
import { Feature } from "flatgeobuf/lib/mjs/flat-geobuf/feature.js";
import { Header } from "flatgeobuf/lib/mjs/flat-geobuf/header.js";
import { buildGeometry } from "flatgeobuf/lib/mjs/generic/geometry.js";
import { parseGC, parseGeometry } from "flatgeobuf/lib/mjs/geojson/geometry.js";

const encoder = new TextEncoder();

export const T = { Byte: 0, UByte: 1, Bool: 2, Short: 3, UShort: 4, Int: 5, UInt: 6, Long: 7, ULong: 8, Float: 9, Double: 10, String: 11, Json: 12, DateTime: 13, Binary: 14 };
export const G = { Unknown: 0, Point: 1, LineString: 2, Polygon: 3, MultiPoint: 4, MultiLineString: 5, MultiPolygon: 6, GeometryCollection: 7 };
// The x, y box of a GeoJSON geometry (NaN for none).
export function bboxOf(g) {
  const b = [Infinity, Infinity, -Infinity, -Infinity];
  const walk = (c) => {
    if (typeof c[0] === "number") {
      b[0] = Math.min(b[0], c[0]);
      b[1] = Math.min(b[1], c[1]);
      b[2] = Math.max(b[2], c[0]);
      b[3] = Math.max(b[3], c[1]);
    } else c.forEach(walk);
  };
  if (g) (g.type === "GeometryCollection" ? g.geometries : [g]).forEach((m) => m.coordinates && walk(m.coordinates));
  return b[0] <= b[2] ? b : [NaN, NaN, NaN, NaN];
}

function propertyBytes(columns, properties) {
  const out = [];
  const push = (n, set) => {
    const b = new Uint8Array(n);
    set(new DataView(b.buffer));
    out.push(b);
  };
  columns.forEach(({ name, type }, i) => {
    const v = properties?.[name];
    if (v === undefined || v === null) return;
    push(2, (d) => d.setUint16(0, i, true));
    const text = (s) => {
      const b = typeof s === "string" ? encoder.encode(s) : s;
      push(4, (d) => d.setUint32(0, b.length, true));
      out.push(b);
    };
    switch (type) {
      case T.Byte: return push(1, (d) => d.setInt8(0, v));
      case T.UByte: return push(1, (d) => d.setUint8(0, v));
      case T.Bool: return push(1, (d) => d.setUint8(0, v ? 1 : 0));
      case T.Short: return push(2, (d) => d.setInt16(0, v, true));
      case T.UShort: return push(2, (d) => d.setUint16(0, v, true));
      case T.Int: return push(4, (d) => d.setInt32(0, v, true));
      case T.UInt: return push(4, (d) => d.setUint32(0, v, true));
      case T.Long: return push(8, (d) => d.setBigInt64(0, BigInt(v), true));
      case T.ULong: return push(8, (d) => d.setBigUint64(0, BigInt(v), true));
      case T.Float: return push(4, (d) => d.setFloat32(0, v, true));
      case T.Double: return push(8, (d) => d.setFloat64(0, v, true));
      case T.Json: return text(typeof v === "string" ? v : JSON.stringify(v));
      default: return text(v);
    }
  });
  const all = new Uint8Array(out.reduce((s, b) => s + b.length, 0));
  let at = 0;
  for (const b of out) {
    all.set(b, at);
    at += b.length;
  }
  return all;
}

function featureBytes(columns, f) {
  const builder = new flatbuffers.Builder();
  const g = f.geometry ? buildGeometry(builder, f.geometry.type === "GeometryCollection" ? parseGC(f.geometry) : parseGeometry(f.geometry)) : 0;
  const p = propertyBytes(columns, f.properties);
  const props = p.length > 0 ? Feature.createPropertiesVector(builder, p) : 0;
  Feature.startFeature(builder);
  if (g) Feature.addGeometry(builder, g);
  if (props) Feature.addProperties(builder, props);
  builder.finishSizePrefixed(Feature.endFeature(builder));
  return builder.asUint8Array();
}

function headerBytes({ geometryType, columns, count, nodeSize, crs }) {
  const builder = new flatbuffers.Builder();
  const cols = columns.map(({ name, type }) => {
    const n = builder.createString(name);
    Column.startColumn(builder);
    Column.addName(builder, n);
    Column.addType(builder, type);
    return Column.endColumn(builder);
  });
  const colVector = cols.length > 0 ? Header.createColumnsVector(builder, cols) : 0;
  let crsAt = 0;
  if (crs) {
    const org = crs.org ? builder.createString(crs.org) : 0;
    const wkt = crs.wkt ? builder.createString(crs.wkt) : 0;
    Crs.startCrs(builder);
    if (org) Crs.addOrg(builder, org);
    if (crs.code) Crs.addCode(builder, crs.code);
    if (wkt) Crs.addWkt(builder, wkt);
    crsAt = Crs.endCrs(builder);
  }
  const name = builder.createString("cases");
  Header.startHeader(builder);
  Header.addName(builder, name);
  Header.addGeometryType(builder, geometryType);
  if (colVector) Header.addColumns(builder, colVector);
  Header.addFeaturesCount(builder, BigInt(count));
  Header.addIndexNodeSize(builder, nodeSize);
  if (crsAt) Header.addCrs(builder, crsAt);
  builder.finishSizePrefixed(Header.endHeader(builder));
  return builder.asUint8Array();
}

// A packed R-tree over `boxes` (in feature order) whose leaves point at `offsets`, as flatgeobuf lays it out.
function treeBytes(boxes, offsets, nodeSize) {
  const n = boxes.length;
  const sizes = [n];
  for (let k = n; k !== 1 || sizes.length === 1;) {
    k = Math.ceil(k / nodeSize);
    sizes.push(k);
    if (k === 1) break;
  }
  const total = sizes.reduce((s, k) => s + k, 0);
  const nodes = new Float64Array(total * 4);
  const refs = new Array(total).fill(0n);
  let levelStart = total - n;
  boxes.forEach((b, i) => {
    nodes.set(b.map((v) => (Number.isNaN(v) ? 0 : v)), (levelStart + i) * 4);
    refs[levelStart + i] = BigInt(offsets[i]);
  });
  for (let l = 1; l < sizes.length; l++) {
    const childStart = levelStart;
    levelStart -= sizes[l];
    for (let i = 0; i < sizes[l]; i++) {
      const box = [Infinity, Infinity, -Infinity, -Infinity];
      for (let c = childStart + i * nodeSize; c < Math.min(childStart + (i + 1) * nodeSize, childStart + sizes[l - 1]); c++) {
        box[0] = Math.min(box[0], nodes[c * 4]);
        box[1] = Math.min(box[1], nodes[c * 4 + 1]);
        box[2] = Math.max(box[2], nodes[c * 4 + 2]);
        box[3] = Math.max(box[3], nodes[c * 4 + 3]);
      }
      nodes.set(box, (levelStart + i) * 4);
      refs[levelStart + i] = BigInt(childStart + i * nodeSize);
    }
  }
  const out = new Uint8Array(total * 40);
  const v = new DataView(out.buffer);
  for (let i = 0; i < total; i++) {
    for (let k = 0; k < 4; k++) v.setFloat64(i * 40 + k * 8, nodes[i * 4 + k], true);
    v.setBigUint64(i * 40 + 32, refs[i], true);
  }
  return out;
}

/** A FlatGeobuf file of `features` (`columns`: `{ name, type }`, the first `headerColumns` in its header), indexed unless `nodeSize` is 0. */
export function fgbFile(features, { columns = [], geometryType = G.Unknown, nodeSize = 16, crs = null, headerColumns = columns.length } = {}) {
  const fs = features.map((f) => featureBytes(columns, f));
  const header = headerBytes({ geometryType, columns: columns.slice(0, headerColumns), count: features.length, nodeSize, crs });
  const offsets = [];
  let at = 0;
  for (const f of fs) {
    offsets.push(at);
    at += f.length;
  }
  const tree = nodeSize > 0 && features.length > 0 ? treeBytes(features.map((f) => bboxOf(f.geometry)), offsets, nodeSize) : new Uint8Array(0);
  const parts = [Uint8Array.from([0x66, 0x67, 0x62, 3, 0x66, 0x67, 0x62, 1]), header, tree, ...fs];
  const out = new Uint8Array(parts.reduce((s, b) => s + b.length, 0));
  at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
}

// The columns `features` need: numbers as Double, strings as String, booleans as Bool, the rest as Json.
export function columnsOf(features) {
  const types = new Map();
  for (const f of features) {
    for (const [k, v] of Object.entries(f.properties ?? {})) {
      if (v === null || types.has(k)) continue;
      types.set(k, typeof v === "number" ? T.Double : typeof v === "string" ? T.String : typeof v === "boolean" ? T.Bool : T.Json);
    }
  }
  return [...types].map(([name, type]) => ({ name, type }));
}
