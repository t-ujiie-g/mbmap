// Read for every tile, apart from query.mjs, which loads with the first query.
import { readValue } from "./values.mjs";

/**
 * Feature ranges from the wasm (docs/FORMATS.md, "Feature ranges") by packed entry: each
 * feature id (as `String(id)`, how feature state keys it) to the `[first, count, outline first,
 * outline count, ...]` indices of its features (several features may share an id).
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
        for (let j = 0; j < 4; j++) list.push(view.getUint32(at + j * 4, true));
      }
      at += 16;
    }
    out.set(entry, byId);
  }
  return out;
}

/** The ranges of features `ids` in a tile's `ranges`, per entry as [first, count, outline first, outline count, index in `ids`]. */
export function rangesOf(ranges, ids) {
  const out = [];
  for (const [entry, byId] of ranges) {
    const found = [];
    ids.forEach((id, k) => {
      const r = byId.get(id) ?? [];
      for (let i = 0; i < r.length; i += 4) found.push(r[i], r[i + 1], r[i + 2], r[i + 3], k);
    });
    if (found.length > 0) out.push({ entry, ranges: found });
  }
  return out;
}
