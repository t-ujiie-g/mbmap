// Query results from the wasm (docs/FORMATS.md, "Query result") as GeoJSON
// features. Geometry follows @mapbox/vector-tile 3.0.0's `toGeoJSON`
// (BSD-3-Clause, Copyright (c) 2024, Mapbox; see NOTICE), as MapLibre returns it.
import { readString, readValue } from "./values.mjs";

/** The rings' polygons: an outer ring and its holes each (`classifyRings`). */
export function classifyRings(rings) {
  if (rings.length <= 1) return [rings];
  const polygons = [];
  let polygon;
  let ccw;
  for (const ring of rings) {
    let area = 0;
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      area += (ring[j][0] - ring[i][0]) * (ring[i][1] + ring[j][1]);
    }
    if (area === 0) continue;
    ccw ??= area < 0;
    if (ccw === area < 0) {
      if (polygon) polygons.push(polygon);
      polygon = [ring];
    } else if (polygon) {
      polygon.push(ring);
    }
  }
  if (polygon) polygons.push(polygon);
  return polygons;
}

/** GeoJSON geometry of `rings` (tile units of a tile `extent` wide) of a feature of `type` (1 point, 2 line, 3 polygon) in tile z/x/y. */
export function toGeometry(type, rings, extent, z, x, y) {
  const size = extent * 2 ** z;
  const x0 = extent * x;
  const y0 = extent * y;
  const project = ([px, py]) => [
    ((px + x0) * 360) / size - 180,
    (360 / Math.PI) * Math.atan(Math.exp((1 - ((py + y0) * 2) / size) * Math.PI)) - 90,
  ];
  if (type === 1) {
    const points = rings.flat().map(project);
    return points.length === 1 ? { type: "Point", coordinates: points[0] } : { type: "MultiPoint", coordinates: points };
  }
  if (type === 2) {
    const lines = rings.map((r) => r.map(project));
    return lines.length === 1 ? { type: "LineString", coordinates: lines[0] } : { type: "MultiLineString", coordinates: lines };
  }
  const polygons = classifyRings(rings).map((p) => p.map((r) => r.map(project)));
  return polygons.length === 1 ? { type: "Polygon", coordinates: polygons[0] } : { type: "MultiPolygon", coordinates: polygons };
}

/**
 * The records of a query result for tile z/x/y: `layer` (style layer index, -1 for a source query),
 * `index` (feature index in its layer), `distance` (clip depth for extrusions, else NaN) and `feature`.
 * Properties are prototype-less objects, so a tile's `__proto__` key stays a plain key.
 */
export function readQueryResult(bytes, z, x, y) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const count = view.getUint32(0, true);
  const out = [];
  let at = 4;
  for (let n = 0; n < count; n++) {
    const layer = view.getInt32(at, true);
    const index = view.getUint32(at + 4, true);
    const distance = view.getFloat64(at + 8, true);
    let id;
    [id, at] = readValue(view, bytes, at + 16);
    const type = view.getUint8(at);
    const extent = view.getUint32(at + 1, true);
    const ringCount = view.getUint32(at + 5, true);
    at += 9;
    const lengths = [];
    for (let r = 0; r < ringCount; r++, at += 4) lengths.push(view.getUint32(at, true));
    const rings = lengths.map((len) => {
      const ring = [];
      for (let k = 0; k < len; k++, at += 8) ring.push([view.getInt32(at, true), view.getInt32(at + 4, true)]);
      return ring;
    });
    const properties = Object.create(null);
    const props = view.getUint32(at, true);
    at += 4;
    for (let p = 0; p < props; p++) {
      let key;
      let value;
      [key, at] = readString(view, bytes, at);
      [value, at] = readValue(view, bytes, at);
      properties[key] = value;
    }
    const feature = { type: "Feature", geometry: type >= 1 && type <= 3 ? toGeometry(type, rings, extent, z, x, y) : null, properties };
    if (id != null) feature.id = id;
    out.push({ layer, index, distance, feature });
  }
  return out;
}

/**
 * Feature ranges from the wasm (docs/FORMATS.md, "Feature ranges") by packed entry: each
 * feature id (as `String(id)`, how feature state keys it) to the `[first, count, ...]` indices of
 * its features (several features may share an id).
 */
export function readFeatureRanges(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const out = new Map();
  const entries = view.getUint32(0, true);
  let at = 4;
  for (let e = 0; e < entries; e++) {
    const entry = view.getUint32(at, true);
    const n = view.getUint32(at + 4, true);
    at += 8;
    const byId = new Map();
    for (let k = 0; k < n; k++) {
      let id;
      [id, at] = readValue(view, bytes, at);
      if (id != null) {
        const key = String(id);
        let list = byId.get(key);
        if (!list) byId.set(key, (list = []));
        list.push(view.getUint32(at, true), view.getUint32(at + 4, true));
      }
      at += 8;
    }
    out.set(entry, byId);
  }
  return out;
}

/** The ranges of features `ids` in a tile's `ranges`, per entry as [first, count, index in `ids`] triples. */
export function rangesOf(ranges, ids) {
  const out = [];
  for (const [entry, byId] of ranges) {
    const triples = [];
    ids.forEach((id, k) => {
      const r = byId.get(id) ?? [];
      for (let i = 0; i < r.length; i += 2) triples.push(r[i], r[i + 1], k);
    });
    if (triples.length > 0) out.push({ entry, ranges: triples });
  }
  return out;
}
