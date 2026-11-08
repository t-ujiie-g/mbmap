// What `updateData` saves over `setData` in the GeoJSON worker: an edit of a few properties and
// of one geometry on GSI features (国土地理院ベクトルタイル提供実験), as the whole data loaded
// again (setData) and as a diff (updateData), each followed by cutting the z15 tiles of the data,
// in mbmap's wasm-gc tiler and in @maplibre/geojson-vt 6.3.0 (MapLibre's worker).
// Usage: npm run geojson:update-node; writes bench/results/geojson-update-node.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { GeoJSONVT } from "@maplibre/geojson-vt";
import { encodeDiff, loadInput } from "../../geojson_worker/js/diff.mjs";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { ROOT } from "../lib/root.mjs";
import { bboxOf, makeGeoJSONFixtures, tilesFor } from "./fixtures.mjs";

const { gc } = await loadEntry(nodeFetchBytes, nodeImportJs);
const files = await makeGeoJSONFixtures();
const data = JSON.parse(await readFile(files.mixed, "utf8"));
data.features.forEach((f, i) => (f.id = i));
const o = { maxZoom: 18, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 6, extent: 8192, buffer: 2048, wrap: true };
const tiles = tilesFor(bboxOf(data), 15).filter(([z]) => z === 15);
const encoder = new TextEncoder();
const concat = (parts) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) (out.set(p, at), (at += p.length));
  return out;
};

// The median of 7 samples of `f`, each repeated until it took 50 ms, after 300 ms of warming up.
function median(f) {
  for (let t = performance.now(); performance.now() - t < 300; ) f();
  const samples = [];
  for (let s = 0; s < 7; s++) {
    let n = 0;
    const t = performance.now();
    while (performance.now() - t < 50) (f(), n++);
    samples.push((performance.now() - t) / n);
  }
  return samples.sort((a, b) => a - b)[3];
}

const mbLoad = (fc) => {
  const input = concat(loadInput(undefined, encoder.encode(JSON.stringify(fc))));
  gc.exports.geojson_tiler_diffs_mem(gc.copyIn(input), input.length, o.maxZoom, o.indexMaxZoom, o.indexMaxPoints, o.tolerance, o.extent, o.buffer, 1, 0);
};
const mbTiles = () => {
  for (const [z, x, y] of tiles) gc.exports.geojson_tile_bytes_hash(z, x, y);
};
const vtTiles = (index) => {
  for (const [z, x, y] of tiles) index.getTile(z, x, y);
};

const edits = {
  "properties of 10 features": (k) => ({ update: Array.from({ length: 10 }, (_, i) => ({ id: i * 997, addOrUpdateProperties: [{ key: "edited", value: k }] })) }),
  "geometry of 1 feature": (k) => ({ update: [{ id: 1234, newGeometry: { type: "Point", coordinates: [139.765 + (k % 10) * 1e-4, 35.68] } }] }),
};

const results = [];
for (const [name, edit] of Object.entries(edits)) {
  let k = 0;
  // setData: the whole data again, with the edit applied, then the tiles.
  const edited = structuredClone(data);
  const full = {
    mbmap: median(() => (mbLoad(edited), mbTiles())),
    "geojson-vt": median(() => vtTiles(new GeoJSONVT(edited, { ...o, updateable: true }))),
  };
  mbLoad(data);
  const ref = new GeoJSONVT(data, { ...o, updateable: true });
  mbTiles();
  vtTiles(ref);
  const diff = {
    mbmap: median(() => {
      const bytes = encodeDiff(edit(k++));
      gc.exports.geojson_update_mem(gc.copyIn(bytes), bytes.length);
      mbTiles();
    }),
    "geojson-vt": median(() => {
      ref.updateData(edit(k++));
      vtTiles(ref);
    }),
  };
  results.push({ edit: name, setData: full, updateData: diff });
  console.log(`${name}: setData mbmap ${full.mbmap.toFixed(1)} ms, geojson-vt ${full["geojson-vt"].toFixed(1)} ms; updateData mbmap ${diff.mbmap.toFixed(2)} ms, geojson-vt ${diff["geojson-vt"].toFixed(2)} ms`);
}

const out = { env: { runtime: `node ${process.version}`, v8: process.versions.v8 }, features: data.features.length, tiles: tiles.length, results };
await writeFile(path.join(ROOT, "bench/results/geojson-update-node.json"), JSON.stringify(out, null, 2) + "\n");
