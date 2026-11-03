// Cluster features from the wasm (docs/FORMATS.md, "Cluster features") as
// GeoJSON points, as MapLibre's cluster methods give them.
import { readString, readValue } from "../../worker/js/values.mjs";

/** The features in `bytes`; properties are prototype-less objects, so a `__proto__` key stays a plain key. */
export function readClusterFeatures(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const count = view.getUint32(0, true);
  const out = [];
  let at = 4;
  for (let n = 0; n < count; n++) {
    const coordinates = [view.getFloat64(at, true), view.getFloat64(at + 8, true)];
    let id;
    [id, at] = readValue(view, bytes, at + 16);
    const properties = Object.create(null);
    const props = view.getUint32(at, true);
    at += 4;
    for (let p = 0; p < props; p++) {
      let key;
      [key, at] = readString(view, bytes, at);
      [properties[key], at] = readValue(view, bytes, at);
    }
    const feature = { type: "Feature", geometry: { type: "Point", coordinates }, properties };
    if (id !== undefined && id !== null) feature.id = id;
    out.push(feature);
  }
  return out;
}
