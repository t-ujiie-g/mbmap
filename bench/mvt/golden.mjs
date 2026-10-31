// Golden test: every bench fixture decoded by mbmap's mvt (js build) must equal
// @mapbox/vector-tile's output, and the wasm-gc build must agree on the totals.
import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { ROOT } from "../lib/root.mjs";
import { referenceJson, referenceTotals, loadWasmGc } from "./reference.mjs";

const manifest = JSON.parse(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap.manifest.json"), "utf8"));
const mbt = await import(pathToFileURL(path.join(ROOT, "_build/js/release/build/bench/mvt/entry/entry.js")).href);
const gc = await loadWasmGc((rel) => readFile(path.join(ROOT, rel)));

function firstDiff(a, b, where = "") {
  if (typeof a !== typeof b || Array.isArray(a) !== Array.isArray(b)) return `${where}: ${JSON.stringify(a)?.slice(0, 80)} vs ${JSON.stringify(b)?.slice(0, 80)}`;
  if (a === null || typeof a !== "object") return Object.is(a, b) ? null : `${where}: ${a} vs ${b}`;
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  for (const k of keys) {
    const d = firstDiff(a[k], b[k], `${where}/${k}`);
    if (d) return d;
  }
  return null;
}

let failures = 0, features = 0;
for (const key of Object.keys(manifest.tiles)) {
  const buf = new Uint8Array(await readFile(path.join(ROOT, `bench/fixtures/gsi-bvmap/${key}.pbf`)));
  const ref = referenceJson(new VectorTile(new PbfReader(buf)));
  const text = mbt.tile_to_json(buf);
  if (text.startsWith("error:")) { failures++; console.log(`FAIL ${key}: ${text}`); continue; }
  const diff = firstDiff(JSON.parse(text), ref);
  const totals = referenceTotals(new VectorTile(new PbfReader(buf)));
  const gcTotals = gc.decode(buf);
  const totalsOk = gcTotals.points === totals.points && gcTotals.properties === totals.properties && gcTotals.coordSum === totals.coordSum;
  for (const l of Object.values(ref)) features += l.features.length;
  if (diff || !totalsOk) {
    failures++;
    console.log(`FAIL ${key}: ${diff ?? `wasm-gc totals ${JSON.stringify(gcTotals)} vs ${JSON.stringify(totals)}`}`);
  }
}
const n = Object.keys(manifest.tiles).length;
console.log(`${n - failures}/${n} tiles identical to @mapbox/vector-tile (${features} features); wasm-gc totals checked`);
process.exitCode = failures ? 1 : 0;
