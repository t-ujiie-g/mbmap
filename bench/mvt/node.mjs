// mvt decode bench in Node; writes bench/results/mvt-decode-node.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { ROOT } from "../lib/root.mjs";
import { loadWasmGc, referenceTotals } from "./reference.mjs";
import { decoders, runDecodeBench, printRows } from "./bench-core.mjs";

const manifest = JSON.parse(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap.manifest.json"), "utf8"));
const tiles = [];
for (const key of Object.keys(manifest.tiles)) {
  const buf = new Uint8Array(await readFile(path.join(ROOT, `bench/fixtures/gsi-bvmap/${key}.pbf`)));
  tiles.push({ key, buf, points: referenceTotals(new VectorTile(new PbfReader(buf))).points });
}
const mbtJs = await import(pathToFileURL(path.join(ROOT, "_build/js/release/build/bench/mvt/entry/entry.js")).href);
const gc = await loadWasmGc((rel) => readFile(path.join(ROOT, rel)));
const result = runDecodeBench(tiles, decoders({ mbtJs, gc }));
const out = { env: { runtime: `node ${process.version}`, v8: process.versions.v8 }, ...result };
await writeFile(path.join(ROOT, "bench/results/mvt-decode-node.json"), JSON.stringify(out, null, 2) + "\n");
printRows(result);
