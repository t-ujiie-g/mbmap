// Golden test: tiler's updates must cut every tile in range as @maplibre/geojson-vt 6.3.0 with
// `updateable: true` does after the same seeded `updateData` diffs (ids, properties and order
// included; js in full, wasm-gc by hash), clusters and clusterProperties too (wasm-gc without
// clusterProperties, as cluster:golden). GSI data: 国土地理院ベクトルタイル提供実験.
// Usage: npm run geojson:diffs (SETS=mixed,world,clusters-points,clusters-random for some); writes bench/results/geojson-diffs-golden.json and must stay 0 differ.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { GeoJSONVT } from "@maplibre/geojson-vt";
import { createExpression } from "@maplibre/maplibre-gl-style-spec";
import { encodeDiff, loadInput } from "../../geojson_worker/js/diff.mjs";
import { readClusterFeatures } from "../../geojson_worker/js/features.mjs";
import { readString, readValue } from "../../worker/js/values.mjs";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { ROOT } from "../lib/root.mjs";
import { bboxOf, makeGeoJSONFixtures, tilesFor } from "./fixtures.mjs";

const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);
const encoder = new TextEncoder();

const OPTION_SETS = {
  maplibre: { maxZoom: 18, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 6, extent: 8192, buffer: 2048, wrap: true },
  defaults: { maxZoom: 14, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 64, wrap: true },
  noWrap: { maxZoom: 14, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 3, extent: 4096, buffer: 64, wrap: false },
  lineMetrics: { maxZoom: 18, indexMaxZoom: 5, indexMaxPoints: 100000, tolerance: 6, extent: 8192, buffer: 2048, wrap: true, lineMetrics: true },
  shallow: { maxZoom: 14, indexMaxZoom: 3, indexMaxPoints: 2000, tolerance: 3, extent: 4096, buffer: 64, wrap: true },
};

const CLUSTER_SETS = {
  maplibre: { buffer: 1024, cluster: { maxZoom: 17, minPoints: 2, radius: 400, extent: 4096 } },
  properties: {
    buffer: 1024, cluster: { maxZoom: 17, minPoints: 2, radius: 400, extent: 4096 },
    properties: { sum: ["+", ["get", "n"]], most: ["max", ["coalesce", ["get", "n"], -1]], kinds: [["concat", ["accumulated"], ["get", "kinds"]], ["get", "kind"]] },
  },
};

let seed = 11;
const rand = () => ((seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) / 4294967296);
const pick = (a) => a[Math.floor(rand() * a.length)];
const copy = (v) => JSON.parse(JSON.stringify(v));
const concat = (parts) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) (out.set(p, at), (at += p.length));
  return out;
};

// MapLibre's `getSuperclusterOptions` for geojson-vt (as cluster:golden).
function clusterFunctions(clusterProperties) {
  const mapExpressions = {};
  const reduceExpressions = {};
  const globals = { accumulated: null, zoom: 0 };
  const feature = { properties: null };
  const keys = Object.keys(clusterProperties);
  for (const key of keys) {
    const [operator, mapExpression] = clusterProperties[key];
    mapExpressions[key] = createExpression(mapExpression, `sources.s.clusterProperties.${key}[1]`).value;
    reduceExpressions[key] = createExpression(typeof operator === "string" ? [operator, ["accumulated"], ["get", key]] : operator, `sources.s.clusterProperties.${key}[0]`).value;
  }
  return {
    map: (pointProperties) => {
      feature.properties = pointProperties;
      const properties = {};
      for (const key of keys) properties[key] = mapExpressions[key].evaluate(globals, feature);
      return properties;
    },
    reduce: (accumulated, clusterProperties) => {
      feature.properties = clusterProperties;
      for (const key of keys) {
        globals.accumulated = accumulated[key];
        accumulated[key] = reduceExpressions[key].evaluate(globals, feature);
      }
    },
  };
}

// A columnar tile (docs/FORMATS.md) as {type, id, props, rings} per feature; null for none.
function readTile(bytes) {
  if (bytes.length === 0) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const [f, r, p, k] = [0, 4, 8, 12].map((o) => view.getUint32(o, true));
  let at = 16;
  const types = [...bytes.subarray(at, at + f)];
  at += Math.ceil(f / 4) * 4;
  const ringEnds = Array.from({ length: f }, (_, i) => view.getUint32(at + i * 4, true));
  at += f * 4;
  const pointEnds = Array.from({ length: r }, (_, i) => view.getUint32(at + i * 4, true));
  at += r * 4;
  const xy = Array.from({ length: p }, (_, i) => [view.getInt16(at + i * 4, true), view.getInt16(at + i * 4 + 2, true)]);
  at = Math.ceil((at + p * 4) / 4) * 4;
  const keys = [];
  for (let i = 0; i < k; i++) {
    let key;
    [key, at] = readString(view, bytes, at);
    keys.push(key);
  }
  const props = types.map(() => ({}));
  for (const key of keys) {
    for (let i = 0; i < f; i++) {
      let v;
      [v, at] = readValue(view, bytes, at);
      if (v !== undefined) props[i][key] = v;
    }
  }
  return types.map((type, i) => {
    let id;
    [id, at] = readValue(view, bytes, at);
    const rings = [];
    for (let ring = i === 0 ? 0 : ringEnds[i - 1]; ring < ringEnds[i]; ring++) {
      rings.push(xy.slice(ring === 0 ? 0 : pointEnds[ring - 1], pointEnds[ring]));
    }
    return { type, id: id ?? null, props: props[i], rings };
  });
}

// Tags as the tile carries them: objects as their JSON, undefined left out, keys sorted.
const tagsText = (tags) => {
  const out = {};
  for (const k of Object.keys(tags ?? {}).sort()) {
    const v = tags[k];
    if (v !== undefined) out[k] = v !== null && typeof v === "object" ? JSON.stringify(v) : v;
  }
  return JSON.stringify(out);
};

function sameTile(ref, ours) {
  if (!ref || !ours) return !ref === !ours;
  if (ref.features.length !== ours.length) return false;
  return ref.features.every((f, i) => {
    const g = ours[i];
    const rings = g.type === 1 ? g.rings.flat(1) : g.rings;
    return f.type === g.type && (f.id ?? null) === g.id && tagsText(f.tags) === tagsText(g.props) &&
      JSON.stringify(f.geometry) === JSON.stringify(rings);
  });
}

function hash(bytes) {
  if (bytes.length === 0) return 0;
  let h = 0x811c9dc5 | 0;
  for (const v of bytes) h = Math.imul(h ^ v, 0x01000193);
  return h;
}

// Features without coordinates, a GeometryCollection, and positions past the antimeridian, for the diffs to reach.
function extras(promoteId, next) {
  const withId = (f) => {
    const id = next();
    if (promoteId) f.properties = { ...f.properties, [promoteId]: id };
    else f.id = id;
    return f;
  };
  return [
    withId({ type: "Feature", properties: { k: 1 }, geometry: null }),
    withId({ type: "Feature", properties: { k: 2 }, geometry: { type: "LineString", coordinates: [] } }),
    withId({ type: "Feature", properties: { k: 3 }, geometry: { type: "GeometryCollection", geometries: [] } }),
    withId({ type: "Feature", properties: { k: 4 }, geometry: { type: "GeometryCollection", geometries: [{ type: "Point", coordinates: [139.76, 35.68] }, { type: "LineString", coordinates: [[139.75, 35.67], [139.77, 35.69]] }] } }),
  ];
}

function emptyGeometry() {
  return pick([{ type: "Point", coordinates: [] }, { type: "Polygon", coordinates: [] }, { type: "GeometryCollection", geometries: [] }]);
}

function randomDiff(model, geometries, promoteId, next, points) {
  const d = {};
  const some = (n, f) => Array.from({ length: Math.floor(rand() * n) }, f);
  const ids = model.size ? [...model] : ["missing"];
  const anyId = () => (rand() < 0.9 ? pick(ids) : "missing");
  const geometry = () => (rand() < 0.1 ? emptyGeometry() : copy(pick(geometries)));
  if (rand() < 0.03) d.removeAll = true;
  if (rand() < 0.5) d.remove = some(8, anyId);
  if (rand() < 0.5) {
    d.add = some(6, () => {
      const id = rand() < 0.3 ? pick(ids) : next();
      const f = { type: "Feature", properties: { added: true, n: Math.floor(rand() * 100), kind: pick(["a", "b"]) }, geometry: rand() < 0.05 ? null : geometry() };
      if (rand() < 0.05) return f;
      if (promoteId) f.properties[promoteId] = id;
      else f.id = id;
      return f;
    });
    if (d.add.length && rand() < 0.2) d.add.push(copy(d.add[0]));
  }
  if (rand() < 0.8) {
    d.update = some(8, () => {
      const u = { id: anyId() };
      if (rand() < 0.4) u.newGeometry = geometry();
      if (rand() < 0.1) u.removeAllProperties = true;
      if (rand() < 0.4) u.removeProperties = some(3, () => pick(["name", "ftCode", "added", "k", "n", "kinds"]));
      if (rand() < 0.6) {
        u.addOrUpdateProperties = some(4, () => ({ key: pick(["name", "k", "added", "z", "n", ...(promoteId ? [promoteId] : [])]), value: rand() < 0.5 ? Math.floor(rand() * 50) : pick(["v", { o: [1] }, null, true]) }));
      }
      return u;
    });
    if (d.update.length && rand() < 0.2) d.update.push({ ...copy(d.update[0]), addOrUpdateProperties: [{ key: "again", value: 1 }] });
  }
  if (points) {
    for (const f of d.add ?? []) if (f.geometry && f.geometry.type !== "Point" && f.geometry.type !== "MultiPoint" && rand() < 0.8) f.geometry = copy(pick(points));
    for (const u of d.update ?? []) if (u.newGeometry && rand() < 0.8) u.newGeometry = copy(pick(points));
  }
  if (d.removeAll) model.clear();
  for (const id of d.remove ?? []) model.delete(id);
  for (const f of d.add ?? []) {
    const id = promoteId ? f.properties?.[promoteId] : f.id;
    if (id != null) model.add(id);
  }
  return d;
}

const files = await makeGeoJSONFixtures();
const load = async (name) => JSON.parse(await readFile(files[name], "utf8"));
let failures = 0;
const counts = { runs: 0, diffs: 0, tiles: 0, features: 0, queries: 0 };
const fail = (what) => {
  if (failures < 10) console.log(what);
  failures++;
};
const results = [];

// Starts both indexes on `data`, then runs `steps` diffs, comparing every tile of `tiles` after each.
function run(name, data, promoteId, steps, tiles, start, update, compare, points) {
  let fresh = 0;
  const next = () => (fresh++ % 2 ? `new${fresh}` : 1e6 + fresh);
  data.features.forEach((f, i) => {
    const id = i % 2 === 0 ? i : `f${i}`;
    if (promoteId) f.properties = { ...f.properties, [promoteId]: id };
    else f.id = id;
  });
  data.features.push(...extras(promoteId, next));
  const model = new Set(data.features.map((f) => (promoteId ? f.properties[promoteId] : f.id)));
  const geometries = data.features.map((f) => f.geometry).filter(Boolean);
  const text = encoder.encode(JSON.stringify(data));
  const input = concat(loadInput(promoteId, text));
  const ref = start(data, input);
  if (!ref) return;
  let compared = 0;
  for (let step = 0; step <= steps; step++) {
    if (step > 0) {
      const diff = randomDiff(model, geometries, promoteId, next, points);
      ref.updateData(copy(diff));
      const bytes = encodeDiff(copy(diff));
      const [a, b] = update(bytes);
      if (a < 0 || b < 0) fail(`${name} step ${step}: diff refused (${a}, ${b})`);
      counts.diffs++;
    }
    for (const [z, x, y] of tiles) compared += compare(ref, z, x, y, `${name} step ${step}`);
  }
  counts.runs++;
  results.push({ run: name, features: data.features.length, steps, tiles: tiles.length, compared });
  console.log(`${name}: ${data.features.length} features, ${steps} diffs, ${compared} tiles; ${failures} differ so far`);
}

const only = process.env.SETS ? process.env.SETS.split(",") : null;
for (const [set, steps, maxZ] of [["mixed", 15, 15], ["world", 40, 4]]) {
  if (only && !only.includes(set)) continue;
  const base = await load(set);
  for (const [setName, o] of Object.entries(OPTION_SETS)) {
    for (const promoteId of setName === "maplibre" ? [undefined, "uid"] : [undefined]) {
      const data = copy(base);
      const tiles = set === "world" ? tilesFor([-180, -85, 180, 85], maxZ) : tilesFor(bboxOf(data), Math.min(o.maxZoom, maxZ));
      run(
        `${set}/${setName}${promoteId ? `/promoteId` : ""}`,
        data,
        promoteId,
        steps,
        tiles,
        (d, input) => {
          const ref = new GeoJSONVT(d, { ...o, updateable: true, promoteId });
          const n = mbt.geojson_tiler_diffs(input, o.maxZoom, o.indexMaxZoom, o.indexMaxPoints, o.tolerance, o.extent, o.buffer, o.wrap, !!o.lineMetrics);
          const m = gc.exports.geojson_tiler_diffs_mem(gc.copyIn(input), input.length, o.maxZoom, o.indexMaxZoom, o.indexMaxPoints, o.tolerance, o.extent, o.buffer, o.wrap ? 1 : 0, o.lineMetrics ? 1 : 0);
          if (n < 0 || m !== n) return fail(`${set}/${setName}: read ${n} (js) and ${m} (wasm-gc) rows`);
          return ref;
        },
        (bytes) => [mbt.geojson_update(bytes), gc.exports.geojson_update_mem(gc.copyIn(bytes), bytes.length)],
        (ref, z, x, y, what) => {
          const t = ref.getTile(z, x, y);
          const bytes = mbt.geojson_tile_bytes(z, x, y);
          counts.tiles++;
          counts.features += t?.features.length ?? 0;
          if (!sameTile(t, readTile(bytes)) || gc.exports.geojson_tile_bytes_hash(z, x, y) !== hash(bytes)) {
            fail(`${what}: tile ${z}/${x}/${y} differs (${t?.features.length ?? "none"} vs ${readTile(bytes)?.length ?? "none"})`);
          }
          return 1;
        },
      );
    }
  }
}

function randomPoints(count) {
  const features = [];
  for (let i = 0; i < count; i++) {
    const p = i % 3 === 0 ? [139.7 + rand() * 0.1, 35.65 + rand() * 0.06] : [-200 + rand() * 400, -85 + rand() * 170];
    const props = { n: i, kind: ["a", "b", "c"][i % 3] };
    features.push({ type: "Feature", properties: props, geometry: i % 7 === 0 ? { type: "MultiPoint", coordinates: [p, [p[0] + 0.001, p[1]]] } : { type: "Point", coordinates: p } });
  }
  return { type: "FeatureCollection", features };
}

const clusterData = { points: await load("points"), random: randomPoints(3000) };
for (const [set, base] of Object.entries(clusterData)) {
  if (only && !only.includes(`clusters-${set}`)) continue;
  for (const [setName, o] of Object.entries(CLUSTER_SETS)) {
    for (const promoteId of setName === "maplibre" ? [undefined, "uid"] : [undefined]) {
      const data = copy(base);
      const c = o.cluster;
      const tiles = set === "points" ? tilesFor(bboxOf(data), 16) : tilesFor([-180, -85, 180, 85], 3);
      const points = data.features.map((f) => f.geometry).filter((g) => g && (g.type === "Point" || g.type === "MultiPoint"));
      const props = o.properties ? encoder.encode(JSON.stringify(o.properties)) : new Uint8Array(0);
      const withGc = !o.properties;
      run(
        `clusters/${set}/${setName}${promoteId ? "/promoteId" : ""}`,
        data,
        promoteId,
        30,
        tiles,
        (d, input) => {
          const fns = o.properties ? clusterFunctions(o.properties) : {};
          const ref = new GeoJSONVT(d, { maxZoom: 18, extent: 4096, buffer: o.buffer, updateable: true, promoteId, cluster: true, clusterOptions: { ...c, ...fns, log: false, generateId: false } });
          const wrapBuffer = o.buffer / 4096;
          const n = mbt.geojson_clusters_diffs(input, c.maxZoom, c.minPoints, c.radius, c.extent, wrapBuffer, props);
          const m = withGc ? gc.exports.geojson_clusters_diffs_mem(gc.copyIn(input), input.length, c.maxZoom, c.minPoints, c.radius, c.extent, wrapBuffer) : n;
          if (n < 0 || m !== n) return fail(`clusters/${set}/${setName}: read ${n} (js) and ${m} (wasm-gc) rows`);
          return ref;
        },
        (bytes) => [mbt.geojson_update(bytes), withGc ? gc.exports.geojson_update_mem(gc.copyIn(bytes), bytes.length) : 0],
        (ref, z, x, y, what) => {
          const t = ref.getTile(z, x, y);
          const bytes = mbt.geojson_cluster(0, z, x, y);
          counts.tiles++;
          counts.features += t?.features.length ?? 0;
          if (!sameTile(t, readTile(bytes)) || (withGc && gc.exports.geojson_cluster_hash(0, z, x, y) !== hash(bytes))) {
            fail(`${what}: cluster tile ${z}/${x}/${y} differs`);
          }
          // A few cluster queries per tile.
          for (const f of (t?.features ?? []).filter((f) => f.tags?.cluster).slice(0, 2)) {
            counts.queries++;
            const id = f.id;
            const leaves = mbt.geojson_cluster(2, id, 5, 1);
            const want = ref.getClusterLeaves(id, 5, 1);
            const got = leaves.length ? readClusterFeatures(leaves) : null;
            const same = got !== null && want.length === got.length && want.every((w, i) => (w.id ?? null) === (got[i].id ?? null) && tagsText(w.properties) === tagsText({ ...got[i].properties }) &&
              w.geometry.coordinates[0] === got[i].geometry.coordinates[0] && w.geometry.coordinates[1] === got[i].geometry.coordinates[1]);
            if (!same || ref.getClusterExpansionZoom(id) !== mbt.geojson_cluster_expansion(id)) fail(`${what}: cluster ${id} queries differ`);
          }
          return 1;
        },
        points,
      );
    }
  }
}

console.log(`${counts.runs} runs, ${counts.diffs} diffs, ${counts.tiles} tiles (${counts.features} features), ${counts.queries} cluster queries compared (js in full, wasm-gc by hash); ${failures} differ`);
await writeFile(path.join(ROOT, "bench/results/geojson-diffs-golden.json"), JSON.stringify({ env: { geojsonVt: "6.3.0" }, results, ...counts, differ: failures }, null, 2) + "\n");
if (failures > 0) process.exit(1);
