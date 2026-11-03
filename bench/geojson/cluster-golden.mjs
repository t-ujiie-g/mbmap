// Golden test: tiler's ClusterIndex must give geojson-vt's ClusterTileIndex tiles (ids and properties
// too) and expansion zooms, children and leaves of the clusters they show (js build in full, wasm-gc
// by hash against it). Usage: node geojson/cluster-golden.mjs
import { readFile } from "node:fs/promises";
import { GeoJSONVT } from "@maplibre/geojson-vt";
import { readClusterFeatures } from "../../geojson_worker/js/features.mjs";
import { readString, readValue } from "../../worker/js/values.mjs";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { bboxOf, makeGeoJSONFixtures, tilesFor } from "./fixtures.mjs";

const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);

// `maplibre` is MapLibre's clustered GeoJSON source (radius 50 px, cluster
// max zoom 17 under maxzoom 18, buffer 128 px) in 4096-unit tiles.
const OPTION_SETS = {
  maplibre: { buffer: 1024, wrap: true, cluster: { maxZoom: 17, minPoints: 2, radius: 400, extent: 4096 } },
  defaults: { buffer: 64, wrap: true, cluster: { maxZoom: 16, minPoints: 2, radius: 40, extent: 512 } },
  wide: { buffer: 1024, wrap: true, cluster: { maxZoom: 12, minPoints: 5, radius: 960, extent: 4096 } },
  noWrap: { buffer: 1024, wrap: false, cluster: { maxZoom: 17, minPoints: 2, radius: 400, extent: 4096 } },
};

// Seeded points over the world, half of them in clumps, some past ±180 and
// near the poles, a few at the same place.
function randomPoints(seed, count) {
  let s = seed;
  const rand = () => ((s = (Math.imul(s, 1103515245) + 12345) >>> 0) / 4294967296);
  const features = [];
  const clumps = Array.from({ length: 30 }, () => [-190 + rand() * 380, -84 + rand() * 168]);
  for (let i = 0; i < count; i++) {
    let p;
    if (i % 2 === 0) {
      const [cx, cy] = clumps[i % clumps.length];
      const r = 10 ** (-4 + rand() * 4);
      p = [cx + (rand() - 0.5) * r, Math.max(-89, Math.min(89, cy + (rand() - 0.5) * r))];
    } else if (i % 97 === 1) {
      p = [179.999, 10];
    } else {
      p = [-200 + rand() * 400, -88 + rand() * 176];
    }
    const props = { n: i, kind: ["a", "b", "c"][i % 3], ok: i % 5 === 0 };
    if (i % 7 === 0) features.push({ type: "Feature", properties: props, geometry: { type: "MultiPoint", coordinates: [p, [p[0] + 0.01, p[1]]] } });
    else features.push({ type: "Feature", properties: props, geometry: { type: "Point", coordinates: p } });
  }
  return { type: "FeatureCollection", features };
}

// A columnar tile (docs/FORMATS.md) as [x, y, id, properties] per feature;
// null for no tile.
function readColumnTile(bytes) {
  if (bytes.length === 0) return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const [f, r, p, k] = [0, 4, 8, 12].map((o) => view.getUint32(o, true));
  if (f !== r || f !== p) throw new Error("a cluster tile has a point per feature");
  let at = 16 + Math.ceil(f / 4) * 4 + 8 * f;
  const xy = [];
  for (let i = 0; i < p; i++, at += 4) xy.push([view.getInt16(at, true), view.getInt16(at + 2, true)]);
  at = Math.ceil(at / 4) * 4;
  const keys = [];
  for (let i = 0; i < k; i++) {
    let key;
    [key, at] = readString(view, bytes, at);
    keys.push(key);
  }
  const props = xy.map(() => ({}));
  for (const key of keys) {
    for (let i = 0; i < f; i++) {
      let v;
      [v, at] = readValue(view, bytes, at);
      if (v !== undefined) props[i][key] = v;
    }
  }
  return xy.map(([x, y], i) => {
    let id;
    [id, at] = readValue(view, bytes, at);
    return [x, y, id ?? null, props[i]];
  });
}

const sorted = (o) => JSON.stringify(o ?? {}, Object.keys(o ?? {}).sort());

function sameTile(ref, ours) {
  if (!ref || !ours) return !ref === !ours;
  if (ref.features.length !== ours.length) return false;
  return ref.features.every((f, i) => {
    const [x, y, id, props] = ours[i];
    return f.geometry[0][0] === x && f.geometry[0][1] === y && (f.id ?? null) === id && sorted(f.tags) === sorted(props);
  });
}

function sameFeatures(ref, ours) {
  if (ref === null || ours.length === 0) return ref === null && ours.length === 0;
  const got = readClusterFeatures(ours);
  if (ref.length !== got.length) return false;
  return ref.every((f, i) => {
    const g = got[i];
    return f.geometry.coordinates[0] === g.geometry.coordinates[0] &&
      f.geometry.coordinates[1] === g.geometry.coordinates[1] &&
      (f.id ?? null) === (g.id ?? null) &&
      sorted(f.properties) === sorted({ ...g.properties });
  });
}

const attempt = (f) => {
  try {
    return f();
  } catch {
    return null;
  }
};

function hash(bytes) {
  if (bytes.length === 0) return 0;
  let h = 0x811c9dc5 | 0;
  for (const v of bytes) h = Math.imul(h ^ v, 0x01000193);
  return h;
}

const files = await makeGeoJSONFixtures();
const datasets = {
  points: JSON.parse(await readFile(files.points, "utf8")),
  world: JSON.parse(await readFile(files.world, "utf8")),
  random: randomPoints(7, 20000),
};

let failures = 0;
const counts = { tiles: 0, features: 0, clusters: 0, queries: 0 };
const fail = (what) => {
  if (failures < 8) console.log(what);
  failures++;
};
for (const [name, data] of Object.entries(datasets)) {
  data.features.forEach((f, i) => (f.id = i));
  const text = new TextEncoder().encode(JSON.stringify(data));
  const addr = gc.copyIn(text);
  for (const [setName, o] of Object.entries(OPTION_SETS)) {
    const c = o.cluster;
    const ref = new GeoJSONVT(data, { maxZoom: 18, extent: 4096, buffer: o.buffer, wrap: o.wrap, cluster: true, clusterOptions: { ...c, log: false, generateId: false } });
    const wrapBuffer = o.buffer / 4096;
    const n = mbt.geojson_clusters(text, c.maxZoom, c.minPoints, c.radius, c.extent, wrapBuffer, o.wrap);
    const m = gc.exports.geojson_clusters_mem(addr, text.length, c.maxZoom, c.minPoints, c.radius, c.extent, wrapBuffer, o.wrap ? 1 : 0);
    if (n !== data.features.length || m !== n) {
      fail(`${name}/${setName}: read ${n} (js) and ${m} (wasm-gc) features, expected ${data.features.length}`);
      continue;
    }
    const tiles = name === "points" ? tilesFor(bboxOf(data), Math.min(c.maxZoom + 2, 20)) : tilesFor([-180, -85, 180, 85], 4);
    const ids = new Set();
    for (const [z, x, y] of tiles) {
      const want = ref.getTile(z, x, y);
      const bytes = mbt.geojson_cluster(0, z, x, y);
      counts.tiles++;
      counts.features += want?.features.length ?? 0;
      for (const f of want?.features ?? []) if (f.tags?.cluster) ids.add(f.id);
      if (!sameTile(want, readColumnTile(bytes)) || gc.exports.geojson_cluster_hash(0, z, x, y) !== hash(bytes)) {
        fail(`${name}/${setName} tile ${z}/${x}/${y} differs`);
      }
    }
    const sample = [...ids].filter((_, i) => i % Math.ceil(ids.size / 1500) === 0);
    counts.clusters += sample.length;
    for (const id of [...sample, -1, 0, 1, 2 ** 31 - 1, ...sample.slice(0, 50).map((i) => i + 1)]) {
      counts.queries += 5;
      if (ref.getClusterExpansionZoom(id) !== mbt.geojson_cluster_expansion(id) || gc.exports.geojson_cluster_expansion(id) !== mbt.geojson_cluster_expansion(id)) {
        fail(`${name}/${setName} expansion zoom of ${id} differs`);
      }
      const queries = [
        [() => ref.getClusterChildren(id), [1, id, 0, 0]],
        [() => ref.getClusterLeaves(id, undefined, undefined), [2, id, 0, 0]],
        [() => ref.getClusterLeaves(id, 5, 3), [2, id, 5, 3]],
        [() => ref.getClusterLeaves(id, Infinity, 0), [2, id, -1, 0]],
      ];
      for (const [want, args] of queries) {
        const bytes = mbt.geojson_cluster(...args);
        if (!sameFeatures(attempt(want), bytes) || gc.exports.geojson_cluster_hash(...args) !== hash(bytes)) {
          fail(`${name}/${setName} ${args[0] === 1 ? "children" : `leaves (${args[2]}, ${args[3]})`} of ${id} differ`);
        }
      }
    }
  }
}
console.log(`${counts.tiles} tiles (${counts.features} features), ${counts.clusters} clusters, ${counts.queries} queries compared (js in full, wasm-gc by hash); ${failures} differ`);
if (failures > 0) process.exit(1);
