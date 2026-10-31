// GeoJSON (already JSON.parse'd) to the bytes of geom's `Table::to_bytes`,
// following formats/geojson.mbt's rules: one row per feature, a
// GeometryCollection one row per member, coordinates beyond x and y dropped,
// a geometry that does not fit its type kept without geometry, objects and
// arrays in properties as JSON text. Pipeline B of the GeoJSON bench.
const KINDS = { Point: 1, MultiPoint: 2, LineString: 3, MultiLineString: 4, Polygon: 5, MultiPolygon: 6 };
const DEPTH = { Point: 0, MultiPoint: 1, LineString: 1, MultiLineString: 2, Polygon: 2, MultiPolygon: 3 };

export function columnarize(data) {
  const kinds = [], partEnds = [], ringEnds = [], pointEnds = [], coords = [];
  const columns = new Map(); // name -> values (undefined = absent)
  let rows = 0;
  const isPos = (p) => Array.isArray(p) && p.length >= 2 && typeof p[0] === "number" && typeof p[1] === "number";
  const fits = (c, d) => {
    if (d === 0) return isPos(c);
    return Array.isArray(c) && c.length > 0 && c.every((x) => fits(x, d - 1));
  };
  const row = (geometry, props) => {
    let kind = 0;
    if (geometry && KINDS[geometry.type] && fits(geometry.coordinates, DEPTH[geometry.type])) {
      kind = KINDS[geometry.type];
      const c = geometry.coordinates;
      const ring = (ps) => { for (const p of ps) coords.push(p[0], p[1]); pointEnds.push(coords.length / 2); };
      if (kind === 1) { ring([c]); ringEnds.push(pointEnds.length); }
      else if (kind === 2 || kind === 3) { ring(c); ringEnds.push(pointEnds.length); }
      else if (kind === 4) for (const l of c) { ring(l); ringEnds.push(pointEnds.length); }
      else if (kind === 5) { for (const r of c) ring(r); ringEnds.push(pointEnds.length); }
      else for (const poly of c) { for (const r of poly) ring(r); ringEnds.push(pointEnds.length); }
    }
    kinds.push(kind);
    partEnds.push(ringEnds.length);
    if (props && typeof props === "object") {
      for (const [k, v] of Object.entries(props)) {
        let col = columns.get(k);
        if (!col) columns.set(k, (col = []));
        col[rows] = v !== null && typeof v === "object" ? JSON.stringify(v) : v;
      }
    }
    rows++;
  };
  const geometries = (g, out) => {
    if (!g) return out;
    if (g.type === "GeometryCollection") for (const m of g.geometries ?? []) geometries(m, out);
    else out.push(g);
    return out;
  };
  const feature = (f) => {
    const gs = geometries(f.geometry, []);
    if (gs.length === 0) row(null, f.properties);
    for (const g of gs) row(g, f.properties);
  };
  if (data.type === "FeatureCollection") data.features.forEach(feature);
  else if (data.type === "Feature") feature(data);
  else for (const g of geometries(data, [])) row(g, null);

  // Encode.
  const enc = new TextEncoder();
  const keys = [...columns.keys()].map((k) => [k, enc.encode(k)]);
  let size = 20 + Math.ceil(kinds.length / 4) * 4 + (partEnds.length + ringEnds.length + pointEnds.length) * 4 + coords.length * 8;
  for (const [, b] of keys) size += 4 + b.length;
  const strings = new Map();
  for (const [k] of keys) {
    const col = columns.get(k);
    for (let i = 0; i < rows; i++) {
      const v = col[i];
      size += 1;
      if (typeof v === "number") size += 8;
      else if (typeof v === "string") { const b = enc.encode(v); strings.set(`${k}\u0000${i}`, b); size += 4 + b.length; }
    }
  }
  const buf = new ArrayBuffer(size);
  const view = new DataView(buf);
  const bytes = new Uint8Array(buf);
  let at = 0;
  const u32 = (v) => { view.setUint32(at, v, true); at += 4; };
  u32(rows); u32(ringEnds.length); u32(pointEnds.length); u32(coords.length / 2); u32(keys.length);
  bytes.set(kinds, at); at += Math.ceil(kinds.length / 4) * 4;
  for (const e of partEnds) u32(e);
  for (const e of ringEnds) u32(e);
  for (const e of pointEnds) u32(e);
  for (const c of coords) { view.setFloat64(at, c, true); at += 8; }
  for (const [, b] of keys) { u32(b.length); bytes.set(b, at); at += b.length; }
  for (const [k] of keys) {
    const col = columns.get(k);
    for (let i = 0; i < rows; i++) {
      const v = col[i];
      if (v === undefined) bytes[at++] = 5;
      else if (v === null) bytes[at++] = 0;
      else if (v === false) bytes[at++] = 1;
      else if (v === true) bytes[at++] = 2;
      else if (typeof v === "number") { bytes[at++] = 3; view.setFloat64(at, v, true); at += 8; }
      else { bytes[at++] = 4; const b = strings.get(`${k}\u0000${i}`); u32(b.length); bytes.set(b, at); at += b.length; }
    }
  }
  return bytes;
}
