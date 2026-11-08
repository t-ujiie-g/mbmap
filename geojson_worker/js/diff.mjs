// What the GeoJSON worker's wasm reads: a source's `promoteId` before its GeoJSON (in the
// worker), and MapLibre's GeoJSONSourceDiff as docs/FORMATS.md "GeoJSON diff" (on the main
// thread, which sends it as bytes). Import-free.

const encoder = new TextEncoder();

/** A Uint8Array of a u32 length, little-endian, and `bytes`. */
function sized(bytes) {
  const out = new Uint8Array(4 + bytes.length);
  new DataView(out.buffer).setUint32(0, bytes.length, true);
  out.set(bytes, 4);
  return out;
}

/** The input of `load`: `promoteId` (a string, else none) and then `data`, the GeoJSON as UTF-8. */
export function loadInput(promoteId, data) {
  return [sized(encoder.encode(typeof promoteId === "string" ? promoteId : "")), data];
}

class Writer {
  constructor() {
    this.bytes = new Uint8Array(256);
    this.view = new DataView(this.bytes.buffer);
    this.at = 0;
  }
  room(n) {
    if (this.at + n <= this.bytes.length) return;
    const next = new Uint8Array(Math.max(this.bytes.length * 2, this.at + n));
    next.set(this.bytes);
    this.bytes = next;
    this.view = new DataView(next.buffer);
  }
  u8(v) {
    this.room(1);
    this.bytes[this.at++] = v;
  }
  u32(v) {
    this.room(4);
    this.view.setUint32(this.at, v, true);
    this.at += 4;
  }
  utf8(s) {
    const b = encoder.encode(s);
    this.u32(b.length);
    this.room(b.length);
    this.bytes.set(b, this.at);
    this.at += b.length;
  }
  // `@geom.write_prop`'s tags (`@core.PROP_*`): objects and arrays as their JSON, as the GeoJSON reader keeps them.
  value(v) {
    if (v === undefined) this.u8(5);
    else if (v === null) this.u8(0);
    else if (typeof v === "boolean") this.u8(v ? 2 : 1);
    else if (typeof v === "number") {
      this.u8(3);
      this.room(8);
      this.view.setFloat64(this.at, v, true);
      this.at += 8;
    } else if (typeof v === "string") (this.u8(4), this.utf8(v));
    else (this.u8(4), this.utf8(JSON.stringify(v) ?? "null"));
  }
  done() {
    return this.bytes.subarray(0, this.at);
  }
}

const isObject = (v) => typeof v === "object" && v !== null;
// An id an object would be in a JavaScript Map: one no feature's id is, so it matches nothing.
const matchable = (id) => !isObject(id);
// geojson-vt reads `geometry` and `properties` only; a geometry that is not an object converts to nothing.
const featureOf = (f) => ({
  type: "Feature",
  ...(f.id !== undefined ? { id: f.id } : {}),
  geometry: isObject(f.geometry) ? f.geometry : null,
  properties: isObject(f.properties) && !Array.isArray(f.properties) ? f.properties : null,
});

/**
 * `diff` as the `update` input: its features (those of `add`, then a new geometry per update
 * with one) as a GeoJSON FeatureCollection, then the rest.
 */
export function encodeDiff(diff) {
  const features = (diff.add ?? []).filter(isObject).map(featureOf);
  const adds = features.length;
  const updates = (diff.update ?? []).filter((u) => isObject(u) && matchable(u.id));
  for (const u of updates) if (u.newGeometry) features.push(featureOf({ geometry: u.newGeometry }));
  const w = new Writer();
  w.u8(diff.removeAll ? 1 : 0);
  const remove = (diff.remove ?? []).filter(matchable);
  w.u32(remove.length);
  for (const id of remove) w.value(id);
  w.u32(adds);
  w.u32(updates.length);
  for (const u of updates) {
    w.value(u.id);
    w.u8((u.newGeometry ? 1 : 0) | (u.removeAllProperties ? 2 : 0));
    const removed = Array.isArray(u.removeProperties) ? u.removeProperties : [];
    w.u32(removed.length);
    for (const k of removed) w.utf8(String(k));
    const added = Array.isArray(u.addOrUpdateProperties) ? u.addOrUpdateProperties.filter(isObject) : [];
    w.u32(added.length);
    for (const p of added) (w.utf8(String(p.key)), w.value(p.value));
  }
  const json = encoder.encode(JSON.stringify({ type: "FeatureCollection", features }));
  const rest = w.done();
  const out = new Uint8Array(4 + json.length + rest.length);
  new DataView(out.buffer).setUint32(0, json.length, true);
  out.set(json, 4);
  out.set(rest, 4 + json.length);
  return out;
}
