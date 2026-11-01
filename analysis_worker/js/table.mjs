// A @geom.Table in its byte form (docs/FORMATS.md, "Table") as a GeoJSON
// FeatureCollection. Import-free, so npm test can load it.

const KINDS = [null, "Point", "MultiPoint", "LineString", "MultiLineString", "Polygon", "MultiPolygon"];

export function tableToGeoJSON(buffer) {
  const v = new DataView(buffer.buffer ?? buffer, buffer.byteOffset ?? 0, buffer.byteLength);
  let at = 0;
  const u32 = () => { const x = v.getUint32(at, true); at += 4; return x; };
  const [f, p, r, n, k] = [u32(), u32(), u32(), u32(), u32()];
  const kinds = Array.from({ length: f }, (_, i) => v.getUint8(at + i));
  at += (f + 3) & ~3;
  const ends = (count) => Array.from({ length: count }, u32);
  const [partEnds, ringEnds, pointEnds] = [ends(f), ends(p), ends(r)];
  const coords = Array.from({ length: n * 2 }, (_, i) => v.getFloat64(at + i * 8, true));
  at += n * 16;
  const decoder = new TextDecoder();
  const utf8 = () => {
    const len = u32();
    const s = decoder.decode(new Uint8Array(v.buffer, v.byteOffset + at, len));
    at += len;
    return s;
  };
  const keys = Array.from({ length: k }, utf8);
  // Tags are @core.PROP_*; 5 marks a feature without the key.
  const value = () => {
    const tag = v.getUint8(at++);
    if (tag === 3) { const x = v.getFloat64(at, true); at += 8; return x; }
    if (tag === 4) return utf8();
    return [null, false, true][tag];
  };
  const props = Array.from({ length: f }, () => []);
  for (const key of keys) {
    for (let i = 0; i < f; i++) {
      const tag = v.getUint8(at);
      if (tag === 5) at++;
      else props[i].push([key, value()]);
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
