// Golden test for tess fills: every polygon feature of every fixture must hash
// identically to MapLibre's pipeline (classifyRings + earcut 3.2.4), in both
// the js and wasm-gc builds; also reports earcut's area deviation per polygon.
import { readFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { ROOT } from "../lib/root.mjs";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { fillFeature, fnv, FNV_SEED } from "./reference.mjs";

const manifest = JSON.parse(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap.manifest.json"), "utf8"));
const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);

let features = 0, polygons = 0, failures = 0, worst = 0, inexact = 0;
for (const key of Object.keys(manifest.tiles)) {
  const buf = new Uint8Array(await readFile(path.join(ROOT, `bench/fixtures/gsi-bvmap/${key}.pbf`)));
  const tile = new VectorTile(new PbfReader(buf));
  const ref = [];
  let total = FNV_SEED;
  for (const layer of Object.values(tile.layers)) {
    for (let i = 0; i < layer.length; i++) {
      const f = layer.feature(i);
      if (f.type !== 3) continue;
      const r = fillFeature(f.loadGeometry());
      ref.push(r.hash);
      total = fnv(total, r.hash);
      for (const d of r.deviations) {
        polygons++;
        if (d > 1e-9) inexact++;
        worst = Math.max(worst, d);
      }
    }
  }
  features += ref.length;
  const got = mbt.fill_digest(buf).split(",").filter(Boolean).map(Number);
  const firstDiff = ref.findIndex((h, i) => h !== got[i]);
  const gcTotal = gc.exports.fill_hash_mem(gc.copyIn(buf), buf.length);
  if (got.length !== ref.length || firstDiff >= 0 || gcTotal !== total) {
    failures++;
    console.log(`FAIL ${key}: ${got.length}/${ref.length} features, first differing feature ${firstDiff}, wasm-gc total ${gcTotal === total ? "ok" : "differs"}`);
  }
}
const n = Object.keys(manifest.tiles).length;
console.log(`${n - failures}/${n} tiles: fills identical to classifyRings + earcut 3.2.4 (${features} polygon features, ${polygons} polygons)`);
console.log(`earcut deviation: max ${worst.toExponential(2)}, ${inexact} polygons above 1e-9`);
process.exitCode = failures ? 1 : 0;
