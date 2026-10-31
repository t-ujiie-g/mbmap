// Golden test: the shipped analysis wasm must give exactly Turf's measures,
// flatbush's search and neighbor order, and Turf's point-in-polygon results
// on every fixture. Usage: node analysis/golden.mjs
import { readFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";
import { nodeFetchBytes } from "../lib/node-io.mjs";
import { makeGeoJSONFixtures } from "../geojson/fixtures.mjs";
import { loadAnalysis, MEASURE } from "./load.mjs";
import * as ref from "./reference.mjs";

const files = await makeGeoJSONFixtures();
const wasm = await loadAnalysis(nodeFetchBytes);
const same = (a, b) => a === b || (Number.isNaN(a) && Number.isNaN(b));
let failures = 0;
const report = (what, got, want) => {
  let differ = 0;
  let first = -1;
  const n = Math.max(got.length, want.length);
  for (let i = 0; i < n; i++) {
    if (!same(got[i], want[i])) {
      differ++;
      if (first < 0) first = i;
    }
  }
  if (differ > 0) {
    failures++;
    console.log(`DIFFER ${what}: ${differ} of ${n} (first at ${first}: ${got[first]} vs ${want[first]})`);
  }
  return n;
};

async function dataset(name, keep = () => true) {
  const all = JSON.parse(await readFile(files[name] ?? path.join(ROOT, `bench/dist/geojson/${name}.geojson`), "utf8"));
  const features = all.features.filter(keep);
  const bytes = new TextEncoder().encode(JSON.stringify({ type: "FeatureCollection", features }));
  return { features, id: wasm.load(bytes) };
}

let compared = 0;
for (const name of ["buildings", "mixed", "world", "roads", "points"]) {
  const { features, id } = await dataset(name);
  compared += report(`${name} area`, wasm.measure(id, MEASURE.area), ref.areas(features));
  compared += report(`${name} length`, wasm.measure(id, MEASURE.length), ref.lengths(features));
  compared += report(`${name} centroid`, wasm.measure(id, MEASURE.centroid), ref.centroids(features));
  const boxes = ref.bboxes(features);
  compared += report(`${name} bbox`, wasm.measure(id, MEASURE.bbox), boxes);
  const ix = ref.index(boxes);
  const q = ref.queries(ref.extentOf(boxes), 200);
  for (const [i, b] of q.boxes.entries()) compared += report(`${name} search ${i}`, wasm.search(id, b), ix.search(...b));
  for (const [i, [x, y]] of q.points.entries()) {
    compared += report(`${name} nearest ${i}`, wasm.nearest(id, x, y, 10), ix.neighbors(x, y, 10));
    compared += report(`${name} nearest-1 ${i}`, wasm.nearest(id, x, y, 1), ix.neighbors(x, y, 1));
  }
  console.log(`${name}: ${features.length} features measured, 200 searches, 400 neighbor queries`);
  wasm.dispose(id);
}

// Points against the polygons of the buildings and of the world set.
const points = await dataset("points");
for (const name of ["buildings", "world"]) {
  const polygons = await dataset(name, ref.isPolygon);
  const ix = ref.index(ref.bboxes(polygons.features));
  const pts = name === "world" ? await dataset("world", (f) => f.geometry.type === "MultiPoint") : points;
  const within = ref.pointsWithin(pts.features, polygons.features, ix);
  compared += report(`${name} pointsWithin`, wasm.within(pts.id, polygons.id), within);
  const property = name === "world" ? "i" : "alti";
  compared += report(`${name} collect`, wasm.collect(polygons.id, points.id, property), ref.collected(polygons.features, points.features, property));
  const b = ref.extentOf(ref.bboxes(pts.features));
  compared += report(`${name} grid`, wasm.grid(pts.id, b, 64, 48), ref.grid(pts.features, b, 64, 48));
  console.log(`${name}: ${within.length} of ${pts.features.length} points within ${polygons.features.length} polygons`);
}

console.log(`${compared} values compared; ${failures === 0 ? "all identical" : `${failures} comparisons differ`}`);
process.exit(failures === 0 ? 0 : 1);
