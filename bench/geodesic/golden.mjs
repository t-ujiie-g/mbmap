// geodesic.wasm vs geographiclib-geodesic 2.2.0 on WGS 84 (inverse, direct, polygons, polylines,
// densified paths); every number must be identical (Object.is).
// Usage: node geodesic/golden.mjs [--cases=N]; writes bench/results/geodesic-golden.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import geodesic from "geographiclib-geodesic";
import { ROOT } from "../lib/root.mjs";

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split("=")[1] ?? d;
const CASES = Number(arg("cases", 20000));
const G = geodesic.Geodesic;
const WGS84 = G.WGS84;

const { instance } = await WebAssembly.instantiate(
  await readFile(path.join(ROOT, "_build/wasm-gc/release/build/geodesic_worker/geodesic_worker.wasm")),
  { Math },
);
const w = instance.exports;
const out = (n) => {
  if (n < 0) throw new Error(n === -2 ? "out of memory" : new TextDecoder().decode(new Uint8Array(w.memory.buffer, w.output_addr(), -n)));
  return new Float64Array(w.memory.buffer.slice(w.output_addr(), w.output_addr() + n * 8));
};
const input = (coords) => {
  const bytes = new Uint8Array(Float64Array.from(coords).buffer);
  new Uint8Array(w.memory.buffer, w.prepare_input(bytes.length), bytes.length).set(bytes);
};

// Mulberry32: the same cases on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(14);
const between = (a, b) => a + (b - a) * rand();

const results = {};
const failures = [];
function check(group, label, want, got) {
  const r = (results[group] ??= { cases: 0, identical: 0 });
  r.cases++;
  const same = want.length === got.length && want.every((v, i) => Object.is(v, got[i]));
  if (same) r.identical++;
  else if (failures.length < 20) failures.push({ group, label, want: Array.from(want), got: Array.from(got) });
}

// Pairs of points: anywhere, close together, nearly antipodal, at the poles, on one meridian, on the equator.
const pairs = [];
for (let i = 0; i < CASES; i++) pairs.push(["random", between(-90, 90), between(-540, 540), between(-90, 90), between(-540, 540)]);
for (let i = 0; i < CASES / 4; i++) {
  const [lat, lon] = [between(-90, 90), between(-180, 180)];
  const d = 10 ** between(-9, -1);
  pairs.push(["short", lat, lon, Math.max(-90, Math.min(90, lat + between(-d, d))), lon + between(-d, d)]);
}
for (let i = 0; i < CASES / 4; i++) {
  const [lat, lon] = [between(-90, 90), between(-180, 180)];
  pairs.push(["antipodal", lat, lon, -lat + between(-1, 1), lon + 180 + between(-1, 1)]);
}
for (let i = 0; i < CASES / 20; i++) {
  pairs.push(["pole", 90 * Math.sign(rand() - 0.5), between(-180, 180), between(-90, 90), between(-180, 180)]);
  const lon = between(-180, 180);
  pairs.push(["meridian", between(-90, 90), lon, between(-90, 90), rand() < 0.5 ? lon : lon + 180]);
  pairs.push(["equator", 0, between(-180, 180), 0, between(-180, 180)]);
}
pairs.push(["edge", 0, 0, 0, 180], ["edge", 90, 0, -90, 0], ["edge", 0, 0, 0, 0], ["edge", -0, -0, 0, 0], ["edge", 20.001, 0, 20.001, 0], ["edge", 91, 0, 0, 0], ["edge", NaN, 0, 0, 0]);

const INV = G.DISTANCE | G.AZIMUTH | G.AREA;
for (const [group, lat1, lon1, lat2, lon2] of pairs) {
  const r = WGS84.Inverse(lat1, lon1, lat2, lon2, INV);
  const label = `${lat1} ${lon1} ${lat2} ${lon2}`;
  check(`inverse ${group}`, label, [r.s12, r.azi1, r.azi2, r.a12, r.S12], out(w.inverse(lat1, lon1, lat2, lon2)));
  const s12 = group === "short" ? r.s12 : between(-2.5e7, 2.5e7);
  const d = WGS84.Direct(lat1, lon1, r.azi1, s12);
  check(`direct ${group}`, label, [d.lat2, d.lon2, d.azi2, d.a12], out(w.direct(lat1, lon1, r.azi1, s12)));
}

// Polygons and polylines: random rings of 3 to 30 vertices of up to 0.01° to 60° across, some around a pole.
for (let i = 0; i < CASES / 10; i++) {
  const n = 3 + Math.floor(rand() * 28);
  const size = 10 ** between(-2, Math.log10(60));
  const [lat0, lon0] = [between(-80, 80), between(-180, 180)];
  const polar = rand() < 0.1;
  const coords = [];
  for (let k = 0; k < n; k++) {
    const t = (2 * Math.PI * k) / n;
    coords.push(polar ? lon0 + (360 * k) / n : lon0 + size * Math.cos(t) * between(0.5, 1), polar ? 85 + between(0, 4) : Math.max(-90, Math.min(90, lat0 + size * Math.sin(t) * between(0.5, 1))));
  }
  if (rand() < 0.5) for (let k = 0; k < n / 2; k++) [coords[2 * k], coords[2 * (n - 1 - k)]] = [coords[2 * (n - 1 - k)], coords[2 * k]];
  for (const closed of [true, false]) {
    const p = WGS84.Polygon(!closed);
    const want = [];
    for (let k = 0; k < n; k++) {
      p.AddPoint(coords[2 * k + 1], coords[2 * k]);
      want.push(p._perimetersum.Sum());
    }
    const r = p.Compute(false, true);
    input(coords);
    check(closed ? "polygon" : "polyline", coords.slice(0, 6).join(" "), [r.perimeter, closed ? r.area : NaN, ...want], out(w.measure_path(closed ? 1 : 0)));
  }
  // Densified: each edge's InverseLine split into equal arcs, longitudes unrolled.
  const step = 10 ** between(3, 6);
  const want = [coords[0], coords[1]];
  let lon = coords[0];
  for (let k = 1; k < n; k++) {
    const line = WGS84.InverseLine(coords[2 * k - 1], lon, coords[2 * k + 1], coords[2 * k]);
    const parts = Math.max(1, Math.ceil(line.s13 / step));
    for (let j = 1; j <= parts; j++) {
      const q = line.ArcPosition((line.a13 / parts) * j, G.LATITUDE | G.LONGITUDE | G.LONG_UNROLL);
      want.push(q.lon2, q.lat2);
    }
    lon = want[want.length - 2];
  }
  input(coords);
  check("densify", `${step} ${coords.slice(0, 4).join(" ")}`, want, out(w.densify(step)));
}

const rows = Object.entries(results).map(([group, r]) => ({ group, ...r }));
console.table(rows);
for (const f of failures) console.log("differs:", f);
await writeFile(path.join(ROOT, "bench/results/geodesic-golden.json"), `${JSON.stringify({ env: { geographiclib: "geographiclib-geodesic 2.2.0", node: process.version }, cases: CASES, rows }, null, 2)}\n`);
if (rows.some((r) => r.identical !== r.cases)) process.exit(1);
