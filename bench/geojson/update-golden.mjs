// npm/src/geojson-diff.ts vs MapLibre 6.16's applySourceDiff, mergeSourceDiffs, getGeoJSONBounds and the tiles its GeoJSONSource
// reloads, over seeded diffs on GSI features (国土地理院ベクトルタイル提供実験) and features crossing the antimeridian.
// Usage: npm run geojson:update; writes bench/results/geojson-update-golden.json and must stay all identical.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import * as ml from "maplibre-src/source/geojson_source_diff.ts";
import { getGeoJSONBounds } from "maplibre-src/util/geojson_bounds.ts";
import { tileIdToLngLatBounds } from "maplibre-src/tile/tile_id_to_lng_lat_bounds.ts";
import { mercatorWorldCoordinateHelper } from "maplibre-src/geo/mercator_coordinate.ts";
import * as mb from "../../npm/src/geojson-diff.ts";
import { bboxOf, makeGeoJSONFixtures, tilesFor } from "./fixtures.mjs";
import { ROOT } from "../lib/root.mjs";

const files = await makeGeoJSONFixtures();
const load = async (name) => JSON.parse(await readFile(files[name], "utf8"));

let seed = 7;
const rand = () => ((seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) / 4294967296);
const pick = (a) => a[Math.floor(rand() * a.length)];
const copy = (v) => structuredClone(v);

// Ids of both kinds, as MapLibre's Map keys them: numbers for even features, strings for odd.
function withIds(fc, promoteId) {
  const features = fc.features.map((f, i) => {
    const id = i % 2 === 0 ? i : `f${i}`;
    return promoteId ? { ...f, properties: { ...f.properties, [promoteId]: id } } : { ...f, id };
  });
  return { type: "FeatureCollection", features };
}

function randomDiff(ids, geometries, promoteId, next) {
  const d = {};
  const some = (n, f) => Array.from({ length: Math.floor(rand() * n) }, f);
  if (rand() < 0.05) d.removeAll = true;
  if (rand() < 0.5) d.remove = some(6, () => (rand() < 0.8 ? pick(ids) : "missing"));
  if (rand() < 0.5) {
    d.add = some(5, () => {
      const id = rand() < 0.3 ? pick(ids) : next();
      const f = { type: "Feature", properties: { added: true }, geometry: copy(pick(geometries)) };
      if (rand() < 0.1) return f;
      if (promoteId) f.properties[promoteId] = id;
      else f.id = id;
      return f;
    });
  }
  if (rand() < 0.7) {
    d.update = some(6, () => {
      const u = { id: rand() < 0.9 ? pick(ids) : "missing" };
      if (rand() < 0.4) u.newGeometry = copy(pick(geometries));
      if (rand() < 0.1) u.removeAllProperties = true;
      if (rand() < 0.4) u.removeProperties = some(3, () => pick(["name", "ftCode", "added", "k", "rnkWidth"]));
      if (rand() < 0.6) u.addOrUpdateProperties = some(4, () => ({ key: pick(["name", "k", "added", "z"]), value: rand() < 0.5 ? rand() : "v" }));
      return u;
    });
  }
  return d;
}

const nonEmpty = (b) => b.getSouthWest() !== undefined;
const boundsOf = (geometries) => geometries.filter(Boolean).map(getGeoJSONBounds).filter(nonEmpty).flatMap((b) => [b.getWest(), b.getSouth(), b.getEast(), b.getNorth()]);

const results = [];
let differ = 0;
const check = (name, ok, details) => {
  if (!ok) {
    differ++;
    if (differ <= 10) console.log(`differ: ${name}`, JSON.stringify(details).slice(0, 400));
  }
};

for (const [set, promoteId] of [["mixed", undefined], ["mixed", "uid"], ["world", undefined]]) {
  const data = withIds(await load(set), promoteId);
  const geometries = data.features.map((f) => f.geometry).filter(Boolean);
  const tiles = tilesFor(bboxOf(data), set === "world" ? 4 : 16);
  const ours = mb.toUpdateable(copy(data), promoteId);
  const theirs = ml.toUpdateable(copy(data), promoteId);
  let fresh = 0;
  const steps = { diffs: 0, merges: 0, tiles: 0, reloads: 0 };
  for (let step = 0; step < 60; step++) {
    const ids = [...theirs.keys()];
    const next = () => (promoteId ? `${promoteId}-${fresh++}` : fresh++ % 2 ? `new${fresh}` : 1e6 + fresh);
    let diff = randomDiff(ids.length ? ids : ["missing"], geometries, promoteId, next);
    if (step % 3 === 0) {
      const later = randomDiff(ids.length ? ids : ["missing"], geometries, promoteId, next);
      const a = mb.mergeSourceDiffs(copy(diff), copy(later), promoteId);
      const b = ml.mergeSourceDiffs(copy(diff), copy(later), promoteId);
      check(`${set} merge ${step}`, JSON.stringify(a) === JSON.stringify(b), { a, b });
      steps.merges++;
      diff = b;
    }
    const affectedOurs = mb.applySourceDiff(ours, copy(diff), promoteId);
    const affectedTheirs = ml.applySourceDiff(theirs, copy(diff), promoteId);
    steps.diffs++;
    check(`${set} data ${step}`, JSON.stringify([...ours.values()]) === JSON.stringify([...theirs.values()]), { step });
    check(`${set} affected ${step}`, JSON.stringify(affectedOurs) === JSON.stringify(affectedTheirs), { step });
    const a = mb.geometryBounds(affectedOurs);
    const b = boundsOf(affectedTheirs);
    check(`${set} bounds ${step}`, JSON.stringify(a) === JSON.stringify(b), { a, b });
    for (const buffer of [0, 0.25]) {
      const boxes = [];
      for (let i = 0; i < b.length; i += 4) boxes.push([[b[i], b[i + 1]], [b[i + 2], b[i + 3]]]);
      for (const [z, x, y] of tiles) {
        const tb = tileIdToLngLatBounds({ z, x: ((x % 2 ** z) + 2 ** z) % 2 ** z, y }, buffer, mercatorWorldCoordinateHelper);
        const want = boxes.some((box) => tb.intersects(box));
        const got = mb.tileMeets(buffer, a, z, ((x % 2 ** z) + 2 ** z) % 2 ** z, y);
        steps.tiles++;
        if (want) steps.reloads++;
        check(`${set} tile ${z}/${x}/${y} step ${step} buffer ${buffer}`, want === got, { want, got });
      }
    }
  }
  results.push({ set, promoteId: promoteId ?? null, features: data.features.length, ...steps });
  console.log(`${set}${promoteId ? ` (promoteId ${promoteId})` : ""}: ${steps.diffs} diffs, ${steps.merges} merges, ${steps.tiles} tiles (${steps.reloads} reloaded)`);
}

// Data diffs refuse: a missing id, a repeated one, something that is not a feature.
for (const [name, data] of [
  ["missing id", { type: "FeatureCollection", features: [{ type: "Feature", properties: {}, geometry: null }] }],
  ["repeated id", { type: "FeatureCollection", features: [{ type: "Feature", id: 1, properties: {}, geometry: null }, { type: "Feature", id: 1, properties: {}, geometry: null }] }],
  ["geometry", { type: "Point", coordinates: [0, 0] }],
  ["null", null],
  ["feature", { type: "Feature", id: 0, properties: {}, geometry: null }],
]) {
  const a = mb.toUpdateable(copy(data));
  const b = ml.toUpdateable(copy(data));
  check(`toUpdateable ${name}`, (a === undefined) === (b === undefined) && JSON.stringify(a && [...a]) === JSON.stringify(b && [...b]), { a, b });
}

console.log(differ === 0 ? "all identical" : `${differ} differ`);
await writeFile(path.join(ROOT, "bench/results/geojson-update-golden.json"), JSON.stringify({ env: { maplibre: "6.16" }, results, differ }, null, 2) + "\n");
process.exitCode = differ === 0 ? 0 : 1;
