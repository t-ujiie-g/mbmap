// proj.wasm (f64 pairs in and out, the host's Math) vs proj4js 2.22.0 point by point, WGS 84 to
// each CRS around Tokyo, median of runs.
// Usage: node proj/node.mjs [--points=N] [--runs=N]; writes bench/results/proj-node.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import proj4 from "proj4";
import { parseProjString } from "../../npm/src/projstring.ts";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";
import { median } from "../lib/rows.mjs";

const POINTS = Number(arg("points", 1_000_000));
const RUNS = Number(arg("runs", 7));
const wasm = await readFile(path.join(ROOT, "_build/wasm-gc/release/build/proj_worker/proj_worker.wasm"));
const { instance } = await WebAssembly.instantiate(wasm, { Math });
const p = instance.exports;

const TOKYO = "+ellps=bessel +towgs84=-146.414,507.337,680.507,0,0,0,0 +units=m +no_defs";
const cases = [
  { name: "plane IX (EPSG:6677)", code: 6677, def: "+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs" },
  { name: "Web Mercator (EPSG:3857)", code: 3857, def: "EPSG:3857" },
  { name: "plane IX on the Tokyo datum (EPSG:30169, 3 parameters)", code: 30169, def: `+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 ${TOKYO}` },
  { name: "Lambert conformal conic, 7 parameters (PROJ string)", def: "+proj=lcc +lat_0=36 +lon_0=139 +lat_1=34 +lat_2=38 +x_0=0 +y_0=0 +ellps=bessel +towgs84=-146.414,507.337,680.507,0.1,0.2,0.3,1.5 +units=m +no_defs" },
];

function input(bytes) {
  const addr = p.prepare_input(bytes.length);
  new Uint8Array(p.memory.buffer, addr, bytes.length).set(bytes);
}
function crsId(c) {
  if (c.code) return c.code;
  input(new Uint8Array(parseProjString(c.def).buffer));
  return -1 - p.define_crs();
}

let seed = 7;
const rand = () => (seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) / 4294967296;
const pts = new Float64Array(POINTS * 2);
for (let i = 0; i < POINTS; i++) {
  pts[i * 2] = 139 + rand();
  pts[i * 2 + 1] = 35 + rand();
}
const bytes = new Uint8Array(pts.buffer);

const rows = [];
for (const c of cases) {
  const id = crsId(c);
  const ours = [];
  const ref = [];
  let diff = 0;
  for (let r = 0; r < RUNS; r++) {
    let t = performance.now();
    input(bytes);
    const n = p.transform_coords(4326, id);
    const out = new Float64Array(p.memory.buffer.slice(p.output_addr(), p.output_addr() + n * 8));
    ours.push(performance.now() - t);
    t = performance.now();
    const conv = proj4("EPSG:4326", c.code === 3857 ? "EPSG:3857" : c.def);
    const res = new Float64Array(POINTS * 2);
    for (let i = 0; i < POINTS; i++) {
      const q = conv.forward([pts[i * 2], pts[i * 2 + 1]]);
      res[i * 2] = q[0];
      res[i * 2 + 1] = q[1];
    }
    ref.push(performance.now() - t);
    for (let i = 0; i < res.length; i++) diff = Math.max(diff, Math.abs(out[i] - res[i]));
  }
  const row = { name: c.name, mbmapMs: median(ours), proj4jsMs: median(ref), maxDiffM: diff };
  rows.push(row);
  console.log(`${c.name}: mbmap ${row.mbmapMs.toFixed(0)} ms, proj4js ${row.proj4jsMs.toFixed(0)} ms (${(row.proj4jsMs / row.mbmapMs).toFixed(2)}x), largest difference ${diff.toExponential(1)} m`);
}
await writeFile(path.join(ROOT, "bench/results/proj-node.json"), JSON.stringify({ node: process.version, points: POINTS, runs: RUNS, rows }, null, 2) + "\n");
