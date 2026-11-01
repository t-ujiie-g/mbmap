// Golden test: proj must transform as proj4js 2.22.0 does, for every CRS it
// supports (longitude/latitude, Web Mercator, Japan's plane rectangular zones
// on JGD2011 and JGD2000, UTM on WGS 84, JGD2011 and JGD2000): random points
// in each CRS's area, forward, inverse and CRS to CRS, js build and wasm-gc.
// Reports the largest differences; fails beyond 1 mm or 1e-8°.
// Usage: node proj/golden.mjs [--points=N]; writes bench/results/proj-golden.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import proj4 from "proj4";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { ROOT } from "../lib/root.mjs";

const arg = (k, d) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split("=")[1] ?? d;
const POINTS = Number(arg("points", 200));
const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);

// Plane rectangular zone origins as proj/crs.mbt has them (GSI).
const ORIGINS = [[33, 129, 30], [33, 131, 0], [36, 132, 10], [33, 133, 30], [36, 134, 20], [36, 136, 0], [36, 137, 10], [36, 138, 30], [36, 139, 50], [40, 140, 50], [44, 140, 15], [44, 142, 15], [44, 144, 15], [26, 142, 0], [26, 127, 30], [26, 124, 0], [26, 131, 0], [20, 136, 0], [26, 154, 0]];
const GRS80 = "+ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs";
const crss = [];
for (const code of [4612, 6668]) {
  proj4.defs(`EPSG:${code}`, "+proj=longlat +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +no_defs");
  crss.push({ code, area: [122, 20, 154, 46] });
}
crss.push({ code: 4326, area: [-180, -85, 180, 85] }, { code: 3857, area: [-180, -85, 180, 85] });
ORIGINS.forEach(([lat, deg, min], i) => {
  const lon = deg + min / 60;
  for (const code of [6669 + i, 2443 + i]) {
    proj4.defs(`EPSG:${code}`, `+proj=tmerc +lat_0=${lat} +lon_0=${lon} +k=0.9999 +x_0=0 +y_0=0 ${GRS80}`);
    crss.push({ code, area: [lon - 2, lat - 2, lon + 2, lat + 2] });
  }
});
for (let zone = 1; zone <= 60; zone++) {
  const lon = zone * 6 - 183;
  crss.push({ code: 32600 + zone, area: [lon - 3, 0, lon + 3, 84] });
  crss.push({ code: 32700 + zone, area: [lon - 3, -80, lon + 3, 0] });
}
for (let zone = 51; zone <= 55; zone++) {
  const lon = zone * 6 - 183;
  for (const code of [6688 + zone - 51, 3097 + zone - 51]) {
    proj4.defs(`EPSG:${code}`, `+proj=utm +zone=${zone} ${GRS80}`);
    crss.push({ code, area: [lon - 3, 20, lon + 3, 46] });
  }
}

let seed = 4242;
const rand = () => (seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) / 4294967296;
const f64 = (pairs) => new Uint8Array(new Float64Array(pairs.flat()).buffer);
function ours(pairs, from, to) {
  const bytes = f64(pairs);
  const js = mbt.proj_bytes(bytes, from, to).split(",").map(Number);
  const addr = gc.copyIn(bytes);
  const out = addr + bytes.length + 64;
  const n = gc.exports.proj_mem(addr, bytes.length, from, to, out);
  const wasm = Array.from(new Float64Array(gc.exports.memory.buffer.slice(out, out + n * 8)));
  return { js, wasm };
}

const worst = { meters: { js: 0, wasm: 0 }, degrees: { js: 0, wasm: 0 } };
const rows = [];
let compared = 0;
function compare(label, pairs, from, to) {
  const ref = pairs.map(([x, y]) => proj4(`EPSG:${from}`, `EPSG:${to}`, [x, y]));
  const { js, wasm } = ours(pairs, from, to);
  const unit = to === 4326 || to === 4612 || to === 6668 ? "degrees" : "meters";
  let max = { js: 0, wasm: 0 };
  ref.forEach(([x, y], i) => {
    for (const [name, got] of [["js", js], ["wasm", wasm]]) {
      const d = Math.max(Math.abs(got[i * 2] - x), Math.abs(got[i * 2 + 1] - y));
      max[name] = Math.max(max[name], Number.isNaN(d) ? Infinity : d);
    }
    compared++;
  });
  worst[unit].js = Math.max(worst[unit].js, max.js);
  worst[unit].wasm = Math.max(worst[unit].wasm, max.wasm);
  rows.push({ label, from, to, unit, maxJs: max.js, maxWasm: max.wasm });
}

for (const crs of crss) {
  const [w, s, e, n] = crs.area;
  const lonlat = Array.from({ length: POINTS }, () => [w + rand() * (e - w), s + rand() * (n - s)]);
  compare("forward", lonlat, 4326, crs.code);
  const xy = lonlat.map(([x, y]) => proj4("EPSG:4326", `EPSG:${crs.code}`, [x, y]));
  compare("inverse", xy, crs.code, 4326);
}
// CRS to CRS: plane IX (Tokyo) to UTM 54 on JGD2011 and to Web Mercator.
const tokyo = Array.from({ length: POINTS }, () => proj4("EPSG:4326", "EPSG:6677", [139.2 + rand(), 35.2 + rand()]));
compare("plane IX to UTM 54", tokyo, 6677, 6691);
compare("plane IX to Web Mercator", tokyo, 6677, 3857);

console.log(`proj golden: ${crss.length} CRSs, ${compared} points; largest difference js ${worst.meters.js.toExponential(2)} m / ${worst.degrees.js.toExponential(2)}°, wasm-gc ${worst.meters.wasm.toExponential(2)} m / ${worst.degrees.wasm.toExponential(2)}°`);
await writeFile(path.join(ROOT, "bench/results/proj-golden.json"), JSON.stringify({ reference: "proj4js 2.22.0", points: POINTS, worst, rows }, null, 2) + "\n");
const bad = rows.filter((r) => (r.unit === "meters" ? 1e-3 : 1e-8) < Math.max(r.maxJs, r.maxWasm));
for (const r of bad.slice(0, 10)) console.log("beyond tolerance:", JSON.stringify(r));
if (bad.length) process.exitCode = 1;
