// viewshed.wasm vs gdal_viewshed processes on viewshed:golden's Mt Fuji DEM (1024 x 1024) and that DEM mirrored
// 4 x 4, observer on the summit; GDAL's net time subtracts a run on a 2 x 2 DEM (startup, drivers, tiny I/O).
// Usage (GDAL on PATH): node viewshed/node.mjs [--runs=5]; writes bench/results/viewshed-node.json.
import { execFileSync, spawnSync } from "node:child_process";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";
import { decodePng } from "../lib/png.mjs";
import { writeInput } from "../../wasmio/js/host.mjs";
import { f64sOf, loadModules, rows, time, writeResults } from "../lib/analysis-modules.mjs";

const RUNS = Number(arg("runs", 5));
if (spawnSync("gdal_viewshed", ["--version"]).status !== 0) {
  console.error("viewshed:node needs GDAL's gdal_viewshed and gdal_translate on PATH");
  process.exit(1);
}
const version = execFileSync("gdal_viewshed", ["--version"]).toString().trim();

const SET = { z: 12, x: [3625, 3628], y: [1616, 1619], dir: "bench/fixtures/gsi-dem-fuji" };
const SIZE = 256;
const [cols, rowsN] = [SET.x[1] - SET.x[0] + 1, SET.y[1] - SET.y[0] + 1];
const [width, height] = [cols * SIZE, rowsN * SIZE];
const rgba = new Uint8Array(width * height * 4);
for (let ty = 0; ty < rowsN; ty++) {
  for (let tx = 0; tx < cols; tx++) {
    const png = decodePng(await readFile(path.join(ROOT, SET.dir, `${SET.z}/${SET.x[0] + tx}/${SET.y[0] + ty}.png`)));
    for (let y = 0; y < SIZE; y++) rgba.set(png.rgba.subarray(y * SIZE * 4, (y + 1) * SIZE * 4), ((ty * SIZE + y) * width + tx * SIZE) * 4);
  }
}
const n = 2 ** SET.z;
const lat = Math.atan(Math.sinh(Math.PI * (1 - (2 * (SET.y[0] + rowsN / 2)) / n))) * 180 / Math.PI;
const res = (40075016.6855785 / n / SIZE) * Math.cos((lat * Math.PI) / 180);

const env = await loadModules("viewshed");
const { a, m } = env;
writeInput(a, [rgba]);
const dem = a.load_dem(width, height, 2, 0, 0, 0, 0, res, res);
const elev = f64sOf(a, a.grid_values(dem, 0)).map((v) => (Number.isNaN(v) ? 0 : v));
// The DEM mirrored `k` x `k` times, so the copies meet without cliffs.
function mirrored(k) {
  const [w, h] = [width * k, height * k];
  const out = new Float64Array(w * h);
  for (let y = 0; y < h; y++) {
    const sy = Math.floor(y / height) % 2 ? height - 1 - (y % height) : y % height;
    for (let x = 0; x < w; x++) {
      const sx = Math.floor(x / width) % 2 ? width - 1 - (x % width) : x % width;
      out[y * w + x] = elev[sy * width + sx];
    }
  }
  return { w, h, values: out };
}

const dir = path.join(ROOT, "bench/dist/viewshed");
await mkdir(dir, { recursive: true });
// A GeoTIFF in EPSG:3857 whose north-west corner is (0, 0), through a raw ENVI file.
async function geotiff(name, w, h, values) {
  const raw = path.join(dir, `${name}.raw`);
  await writeFile(raw, new Uint8Array(values.buffer));
  await writeFile(path.join(dir, `${name}.hdr`), `ENVI\nsamples = ${w}\nlines = ${h}\nbands = 1\nheader offset = 0\nfile type = ENVI Standard\ndata type = 5\ninterleave = bsq\nbyte order = 0\n`);
  const tif = path.join(dir, `${name}.tif`);
  execFileSync("gdal_translate", ["-q", "-of", "GTiff", "-a_srs", "EPSG:3857", "-a_ullr", "0", "0", String(w * res), String(-h * res), raw, tif]);
  return tif;
}
// Wall clock of one gdal_viewshed run, and its CPU (user + sys, to 10 ms) from /usr/bin/time -p.
function gdal(tif, o, format) {
  const out = path.join(dir, format === "MEM" ? "out" : "out.tif");
  const t0 = performance.now();
  const r = spawnSync("/usr/bin/time", ["-p", "gdal_viewshed", "-q", "-ox", String(o.x), "-oy", String(o.y), "-oz", "2", "-tz", "0", "-md", String(o.md), "-cc", "0.85714",
    "-vv", "255", "-iv", "0", "-ov", "0", "-om", "NORMAL", "-of", format, tif, out], { encoding: "utf8" });
  const wall = performance.now() - t0;
  if (r.status !== 0) throw new Error(r.stderr);
  const t = Object.fromEntries(r.stderr.trim().split("\n").map((l) => l.trim().split(/\s+/)).filter((p) => p.length === 2).map(([k, v]) => [k, Number(v) * 1000]));
  return { wall, cpu: t.user + t.sys };
}
const median = (xs) => [...xs].sort((p, q) => p - q)[xs.length >> 1];
function gdalTimes(tif, o, format) {
  gdal(tif, o, format);
  const runs = Array.from({ length: RUNS }, () => gdal(tif, o, format));
  return { wall: median(runs.map((r) => r.wall)), cpu: median(runs.map((r) => r.cpu)) };
}
// What the analysis worker does for `viewshed`: the grid's values out of analysis.wasm, into viewshed.wasm, the
// call, its f64s read.
function ours(grid, w, h, o) {
  const values = f64sOf(a, a.grid_values(grid, 0));
  writeInput(m, [new Uint8Array(values.buffer)]);
  return f64sOf(m, m.viewshed(w, h, 0, res, 0, 0, 0, -res, o.x, o.y, 2, 0, o.md, 0.85714, 6378137, 0, 255, 0, 0));
}

const tiny = await geotiff("tiny", 2, 2, new Float64Array([1, 2, 3, 4]));
const baseline = gdalTimes(tiny, { x: res / 2, y: -res / 2, md: 0 }, "GTiff");
const { all, row } = rows();
for (const k of [1, 4]) {
  const { w, h, values } = k === 1 ? { w: width, h: height, values: elev } : mirrored(k);
  const tif = await geotiff(`dem${k}`, w, h, values);
  writeInput(a, [new Uint8Array(values.buffer)]);
  const grid = a.load_grid(w, h, res, res);
  let top = 0;
  for (let i = 1; i < values.length; i++) if (values[i] > values[top]) top = i;
  for (const md of [0, 5000]) {
    const o = { x: ((top % w) + 0.5) * res, y: -(Math.floor(top / w) + 0.5) * res, md };
    const visible = ours(grid, w, h, o).subarray(8).reduce((s, v) => s + (v === 255), 0);
    const g = gdalTimes(tif, o, "GTiff");
    const mem = gdalTimes(tif, o, "MEM");
    const once = { warmMs: 0, samples: RUNS, sampleMs: 0 };
    const fast = time(() => ours(grid, w, h, o), once);
    const bytes = new Uint8Array(values.buffer);
    const exportOnly = time(() => {
      writeInput(m, [bytes]);
      m.viewshed(w, h, 0, res, 0, 0, 0, -res, o.x, o.y, 2, 0, o.md, 0.85714, 6378137, 0, 255, 0, 0);
    }, once);
    const label = `viewshed ${w} x ${h}, ${md ? `${md} m` : "no"} range (${visible} visible cells)`;
    row(label, g.wall - baseline.wall, fast, { exportOnly, gdalWall: g.wall, gdalCpu: g.cpu, gdalMemWall: mem.wall });
  }
  a.dispose(grid);
}

await writeResults("viewshed-node", {
  gdal: version, runs: RUNS,
  statistic: "median of runs after one warm-up run each",
  columns: "js: GDAL net, the GTiff run's wall clock minus the 2 x 2 run's (baseline); gdalWall / gdalCpu: the GTiff run's wall clock and user + sys; gdalMemWall: wall clock writing to the MEM driver; mbmap: the grid's values out of analysis.wasm, into viewshed.wasm, the call and its output read (one thread); exportOnly: the values copied into viewshed.wasm and the call, its output not read",
  baseline,
}, all);
