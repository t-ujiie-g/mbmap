// `network({ snap })`: route.wasm's noding checked by a brute-force oracle, and routes over GSI roads
// cut to their tiles (examples/shared/tile-lines.js) against the same roads uncut.
// Checks: snap 0 leaves the lines as they are; every end with something to join within snap shares a
// vertex after noding, moved at most 2 × snap, and every vertex added lies on the segment it splits;
// over cut roads with snap no route fails where the uncut roads have one; T-junctions and ends offset
// across a tile edge connect with snap and not without.
// Usage: node route/snap.mjs [--snap=2] [--queries=300]; writes bench/results/route-snap.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import distance from "@turf/distance";
import { hostNumber } from "../../wasmio/js/host.mjs";
import { clipLine, tileBounds, tileLines } from "../../examples/shared/tile-lines.js";
import { ENTRY_JS } from "../lib/entry.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const SNAP = Number(arg("snap", 2));
const QUERIES = Number(arg("queries", 300));
const TILES = [[14551, 6450], [14552, 6450], [14551, 6451], [14552, 6451]];

const entry = await import(path.join(ROOT, ENTRY_JS));
let a;
const { instance: ai } = await WebAssembly.instantiate(
  await readFile(path.join(ROOT, "_build/wasm-gc/release/build/analysis_worker/analysis_worker.wasm")),
  { Math, host: { number: hostNumber(() => a.memory) } },
);
a = ai.exports;
const { instance: ri } = await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/route_worker/route_worker.wasm")), { Math });
const r = ri.exports;
const decoder = new TextDecoder();
const put = (e, bytes) => {
  const at = e.prepare_input(bytes.length);
  new Uint8Array(e.memory.buffer, at, bytes.length).set(bytes);
};
const out = (e, n) => {
  if (n < 0) throw new Error(decoder.decode(out(e, -n)));
  return new Uint8Array(e.memory.buffer.slice(e.output_addr(), e.output_addr() + n));
};
const feature = (coordinates) => ({ type: "Feature", properties: {}, geometry: { type: "LineString", coordinates } });
function network(lines, snap) {
  put(a, new TextEncoder().encode(JSON.stringify({ type: "FeatureCollection", features: lines.map(feature) })));
  const id = a.load();
  put(r, out(a, a.table_out(id)));
  a.dispose(id);
  const handle = r.network_new(1e-5, snap);
  if (handle < 0) throw new Error(decoder.decode(out(r, -handle)));
  return handle;
}
function route(handle, from, to) {
  const v = new Float64Array(out(r, r.network_path(handle, ...from, ...to) * 8).buffer);
  return v.length ? v[0] : null;
}
function snapLines(lines, snap) {
  const v = entry.route_snap(lines.map((l) => l.length), lines.flat(2), snap);
  if (!v.length) return null;
  let at = lines.length;
  return lines.map((_, i) => Array.from({ length: v[i] }, () => [v[at++], v[at++]]));
}

const M_PER_DEG = (6371008.8 * Math.PI) / 180;
// Distance in meters from p to segment a-b in the equirectangular plane at p's latitude.
function toSegment(p, a, b) {
  const c = Math.cos((p[1] * Math.PI) / 180);
  const [ux, uy, vx, vy] = [(a[0] - p[0]) * c, a[1] - p[1], (b[0] - a[0]) * c, b[1] - a[1]];
  const len2 = vx * vx + vy * vy;
  const t = len2 > 0 ? Math.max(0, Math.min(1, -(ux * vx + uy * vy) / len2)) : 0;
  return Math.hypot(ux + t * vx, uy + t * vy) * M_PER_DEG;
}
const meters = (p, q) => distance(p, q) * 1000;

const results = {};
const failures = [];
function fail(group, what) {
  if (failures.length < 20) failures.push({ group, what });
}

// The oracle: what snap_lines must give, checked on `lines` brute force.
function oracle(group, lines, snap) {
  const s = (results[group] = { lines: lines.length, ends: 0, toJoin: 0, joined: 0, added: 0, maxMove: 0 });
  const noded = snapLines(lines, snap);
  if (!noded) return fail(group, "snap_lines gave none");
  const zero = snapLines(lines, 0);
  if (JSON.stringify(zero) !== JSON.stringify(lines)) fail(group, "snap 0 changed the lines");
  const key = (p) => `${p[0]},${p[1]}`;
  const seen = new Map();
  for (const l of noded) for (const p of l) seen.set(key(p), (seen.get(key(p)) ?? 0) + 1);
  const along = lines.map((l) => l.reduce((acc, p, i) => (acc.push(i ? acc[i - 1] + meters(l[i - 1], p) : 0), acc), []));
  const segs = [];
  for (let l = 0; l < lines.length; l++) for (let i = 0; i + 1 < lines[l].length; i++) segs.push([l, i]);
  const limit = snap * (1 - 1e-9);
  for (let l = 0; l < lines.length; l++) {
    const line = lines[l];
    if (line.length < 2) continue;
    const total = along[l][line.length - 1];
    for (const end of [0, line.length - 1]) {
      s.ends++;
      const p = line[end];
      const q = end ? noded[l][noded[l].length - 1] : noded[l][0];
      const move = meters(p, q);
      s.maxMove = Math.max(s.maxMove, move);
      if (move > 2 * snap * (1 + 1e-6)) fail(group, `end ${l}/${end} moved ${move} m`);
      const near = segs.some(([m, i]) => {
        if (m === l && (end === 0 ? along[l][i] : total - along[l][i + 1]) <= 2 * snap) return false;
        return toSegment(p, lines[m][i], lines[m][i + 1]) <= limit;
      });
      const otherEnd = total > 2 * snap && meters(p, line[end ? 0 : line.length - 1]) <= limit;
      if (!near && !otherEnd) continue;
      s.toJoin++;
      if (seen.get(key(q)) >= 2) s.joined++;
      else fail(group, `end ${l}/${end} at ${p} is not joined`);
    }
  }
  // Interior vertices kept in order; each vertex added lies on the segment it splits and is an end's.
  const endKeys = new Set(noded.flatMap((l) => (l.length ? [key(l[0]), key(l[l.length - 1])] : [])));
  for (let l = 0; l < lines.length; l++) {
    const [line, got] = [lines[l], noded[l]];
    let i = 1;
    for (let j = 1; j + 1 < got.length; j++) {
      if (i + 1 < line.length && got[j][0] === line[i][0] && got[j][1] === line[i][1]) {
        i++;
        continue;
      }
      s.added++;
      if (!endKeys.has(key(got[j])) || toSegment(got[j], line[i - 1], line[i]) > 1e-6) fail(group, `vertex ${got[j]} added to line ${l}`);
    }
    if (line.length >= 2 && i !== line.length - 1) fail(group, `line ${l} lost vertices`);
  }
}

// Mulberry32: the same cases on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(2026);

// GSI roads of 2 × 2 tiles: whole as the tiles hold them, and cut to their tiles.
const features = [];
for (const [x, y] of TILES) {
  const tile = new VectorTile(new PbfReader(await readFile(path.join(ROOT, `bench/fixtures/gsi-bvmap/14/${x}/${y}.pbf`))));
  const l = tile.layers.road;
  for (let i = 0; l && i < l.length; i++) features.push({ ...l.feature(i).toGeoJSON(x, y, 14), tile: { z: 14, x, y } });
}
// The uncut roads within the block only, since roads in the tiles' buffers outside it join others.
const [west, south] = tileBounds({ z: 14, x: TILES[0][0], y: TILES[2][1] });
const [, , east, north] = tileBounds({ z: 14, x: TILES[1][0], y: TILES[0][1] });
const whole = features
  .flatMap((f) => (f.geometry.type === "LineString" ? [f.geometry.coordinates] : f.geometry.type === "MultiLineString" ? f.geometry.coordinates : []))
  .flatMap((c) => clipLine(c, [west, south, east, north]));
const cut = tileLines(features);
oracle("gsi cut roads", cut, SNAP);
oracle("gsi cut roads, snap 5", cut, 5);

// Jittered streets with ends short of, past and beside each other.
const streets = [];
for (let k = 0; k < 400; k++) {
  const [x, y] = [139.7 + rand() * 0.01, 35.6 + rand() * 0.01];
  const n = 2 + Math.floor(rand() * 4);
  const dir = rand() * Math.PI * 2;
  const step = 2e-5 + rand() * 2e-4;
  streets.push(Array.from({ length: n }, (_, i) => [x + Math.cos(dir) * step * i + (rand() - 0.5) * 1e-5, y + Math.sin(dir) * step * i + (rand() - 0.5) * 1e-5]));
}
oracle("jittered streets", streets, SNAP);

// Routes between interior vertices of the cut roads, which every network keeps.
const truth = network(whole, 0);
const plain = network(cut, 0);
const snapped = network(cut, SNAP);
const interior = cut.flatMap((l) => l.slice(1, -1));
const rs = (results["gsi routes"] = { queries: QUERIES, truth: 0, plainSame: 0, plainMissing: 0, snappedMissing: 0, same: 0, shorter: 0, maxShorter: 0, longer: 0, maxLonger: 0, newPaths: 0 });
for (let q = 0; q < QUERIES; q++) {
  const pick = () => interior[Math.floor(rand() * interior.length)];
  const [from, to] = [pick(), pick()];
  const [t, p, s] = [route(truth, from, to), route(plain, from, to), route(snapped, from, to)];
  if (t !== null) rs.truth++;
  if (t !== null && p === null) rs.plainMissing++;
  if (t !== null && p !== null && Math.abs(p - t) * 1000 <= 1e-6) rs.plainSame++;
  if (t !== null && s === null) {
    rs.snappedMissing++;
    fail("gsi routes", `${from} -> ${to}: none with snap, ${t} km uncut`);
  }
  if (t === null && s !== null) rs.newPaths++;
  if (t === null || s === null) continue;
  const d = (s - t) * 1000;
  if (Math.abs(d) <= 1e-6) rs.same++;
  else if (d < 0) {
    rs.shorter++;
    rs.maxShorter = Math.max(rs.maxShorter, -d);
  }
  else {
    rs.longer++;
    rs.maxLonger = Math.max(rs.maxLonger, d);
  }
}
for (const h of [truth, plain, snapped]) r.network_dispose(h);

// A T-junction and ends offset across a tile edge (as planetiler cuts them): joined only with snap.
const synthetic = [
  ["T-junction", [[[139.7, 35.6], [139.701, 35.6]], [[139.7005, 35.60001], [139.7005, 35.601]]], [139.7, 35.6], [139.7005, 35.601]],
  ["tile edge", [[[139.7, 35.6], [139.70125, 35.6001]], [[139.70126, 35.600112], [139.7025, 35.6002]]], [139.7, 35.6], [139.7025, 35.6002]],
];
for (const [name, lines, from, to] of synthetic) {
  const [without, withSnap] = [network(lines, 0), network(lines, SNAP)];
  const got = (results[name] = { without: route(without, from, to), with: route(withSnap, from, to) });
  if (got.without !== null || got.with === null) fail(name, `routes ${JSON.stringify(got)}`);
  r.network_dispose(without);
  r.network_dispose(withSnap);
}

console.table(results);
for (const f of failures.slice(0, 10)) console.log(JSON.stringify(f));
const ok = failures.length === 0;
await writeFile(path.join(ROOT, "bench/results/route-snap.json"), JSON.stringify({ snap: SNAP, queries: QUERIES, tiles: TILES, results, failures, ok }, null, 2) + "\n");
console.log(ok ? "all ok" : `${failures.length} failed`);
process.exit(ok ? 0 : 1);
