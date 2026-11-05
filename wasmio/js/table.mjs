// A @geom.Table in its byte form (docs/FORMATS.md, "Table") as a GeoJSON
// FeatureCollection, or its row count and keys. Imports only values.mjs.

import { readString, readValue } from "../../worker/js/values.mjs";

const KINDS = [null, "Point", "MultiPoint", "LineString", "MultiLineString", "Polygon", "MultiPolygon"];

export function tableToGeoJSON(buffer) {
  const v = new DataView(buffer.buffer ?? buffer, buffer.byteOffset ?? 0, buffer.byteLength);
  const bytes = new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
  let at = 0;
  const u32 = () => { const x = v.getUint32(at, true); at += 4; return x; };
  const [f, p, r, n, k] = [u32(), u32(), u32(), u32(), u32()];
  const kinds = Array.from({ length: f }, (_, i) => v.getUint8(at + i));
  at += (f + 3) & ~3;
  const ends = (count) => Array.from({ length: count }, u32);
  const [partEnds, ringEnds, pointEnds] = [ends(f), ends(p), ends(r)];
  const coords = Array.from({ length: n * 2 }, (_, i) => v.getFloat64(at + i * 8, true));
  at += n * 16;
  const keys = Array.from({ length: k }, () => {
    const [s, next] = readString(v, bytes, at);
    at = next;
    return s;
  });
  const props = Array.from({ length: f }, () => []);
  for (const key of keys) {
    for (let i = 0; i < f; i++) {
      const [x, next] = readValue(v, bytes, at);
      at = next;
      if (x !== undefined) props[i].push([key, x]);
    }
  }
  const ring = (i) => {
    const out = [];
    for (let j = i === 0 ? 0 : pointEnds[i - 1]; j < pointEnds[i]; j++) out.push([coords[j * 2], coords[j * 2 + 1]]);
    return out;
  };
  const part = (i) => {
    const out = [];
    for (let j = i === 0 ? 0 : ringEnds[i - 1]; j < ringEnds[i]; j++) out.push(ring(j));
    return out;
  };
  const features = kinds.map((kind, i) => {
    const parts = [];
    for (let j = i === 0 ? 0 : partEnds[i - 1]; j < partEnds[i]; j++) parts.push(part(j));
    const type = KINDS[kind];
    const coordinates =
      type === "Point" ? parts[0][0][0] :
      type === "MultiPoint" ? parts[0][0] :
      type === "LineString" ? parts[0][0] :
      type === "MultiLineString" ? parts.map((q) => q[0]) :
      type === "Polygon" ? parts[0] :
      parts;
    // fromEntries defines keys, so a `__proto__` key stays a plain property.
    return { type: "Feature", geometry: type ? { type, coordinates } : null, properties: Object.fromEntries(props[i]) };
  });
  return { type: "FeatureCollection", features };
}

// `fc`'s features with the ids of `ids`, a property value per feature (docs/FORMATS.md
// "Property values"): each gets its `id` unless absent or null.
export function withIds(fc, ids) {
  const v = new DataView(ids.buffer ?? ids, ids.byteOffset ?? 0, ids.byteLength);
  const bytes = new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
  let at = 0;
  fc.features = fc.features.map((f) => {
    let id;
    [id, at] = readValue(v, bytes, at);
    return id == null ? f : { type: "Feature", id, geometry: f.geometry, properties: f.properties };
  });
  return fc;
}

// The feature count and the property keys of table bytes, read without the rest.
export function tableInfo(buffer) {
  const v = new DataView(buffer.buffer ?? buffer, buffer.byteOffset ?? 0, buffer.byteLength);
  const bytes = new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
  const [f, p, r, n, k] = [0, 4, 8, 12, 16].map((at) => v.getUint32(at, true));
  let at = 20 + ((f + 3) & ~3) + (f + p + r) * 4 + n * 16;
  const columns = [];
  for (let i = 0; i < k; i++) {
    const [s, next] = readString(v, bytes, at);
    columns.push(s);
    at = next;
  }
  return { length: f, columns };
}
