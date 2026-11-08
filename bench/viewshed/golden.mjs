// viewshed.wasm vs GDAL's gdal_viewshed on the Mt Fuji DEM (the mosaic terrain:golden builds, in ground meters
// per cell): observers on the summit, a slope, a valley and the grid's edge, each mode, curvature and range;
// the output's size, geotransform and every cell must be identical. Needs GDAL (3.13) on PATH.
// Usage: node viewshed/golden.mjs; writes bench/results/viewshed-golden.json.
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";
import { nodeFetchBytes } from "../lib/node-io.mjs";
import { decodePng } from "../lib/png.mjs";
import { loadAnalysis } from "../analysis/load.mjs";

if (spawnSync("gdal_viewshed", ["--version"]).status !== 0) {
  console.error("viewshed:golden needs GDAL's gdal_viewshed and gdal_translate on PATH");
  process.exit(1);
}
const version = execFileSync("gdal_viewshed", ["--version"]).toString().trim();

const SET = { z: 12, x: [3625, 3628], y: [1616, 1619], dir: "bench/fixtures/gsi-dem-fuji" };
const SIZE = 256;
const cols = SET.x[1] - SET.x[0] + 1;
const rows = SET.y[1] - SET.y[0] + 1;
const width = cols * SIZE;
const height = rows * SIZE;
const rgba = new Uint8Array(width * height * 4);
for (let ty = 0; ty < rows; ty++) {
  for (let tx = 0; tx < cols; tx++) {
    const png = decodePng(await readFile(path.join(ROOT, SET.dir, `${SET.z}/${SET.x[0] + tx}/${SET.y[0] + ty}.png`)));
    for (let y = 0; y < SIZE; y++) rgba.set(png.rgba.subarray(y * SIZE * 4, (y + 1) * SIZE * 4), ((ty * SIZE + y) * width + tx * SIZE) * 4);
  }
}
const n = 2 ** SET.z;
const lat = Math.atan(Math.sinh(Math.PI * (1 - (2 * (SET.y[0] + rows / 2)) / n))) * 180 / Math.PI;
const res = (40075016.6855785 / n / SIZE) * Math.cos((lat * Math.PI) / 180);

// The elevations as analysis.wasm decodes them (no data as 0 m, for both).
const a = (await loadAnalysis(nodeFetchBytes)).exports;
const at = a.prepare_input(rgba.length);
new Uint8Array(a.memory.buffer, at, rgba.length).set(rgba);
const id = a.load_dem(width, height, 2, 0, 0, 0, 0, res, res);
const cells = a.grid_values(id, 0);
const elev = new Float64Array(a.memory.buffer, a.output_addr(), cells).slice().map((v) => (Number.isNaN(v) ? 0 : v));

// The same grid as a GeoTIFF in EPSG:3857 (semi-major 6378137) whose north-west corner is (0, 0).
const dir = path.join(ROOT, "bench/dist/viewshed");
await mkdir(dir, { recursive: true });
const lines = [`ncols ${width}`, `nrows ${height}`, "xllcorner 0", `yllcorner ${-height * res}`, `cellsize ${res}`];
for (let y = 0; y < height; y++) lines.push(Array.from(elev.subarray(y * width, (y + 1) * width), (v) => String(v)).join(" "));
await writeFile(path.join(dir, "dem.asc"), lines.join("\n") + "\n");
const tif = path.join(dir, "dem.tif");
// AAIGrid reads decimals as Float32 unless told otherwise.
execFileSync("gdal_translate", ["-q", "-oo", "DATATYPE=Float64", "-ot", "Float64", "-a_srs", "EPSG:3857", path.join(dir, "dem.asc"), tif]);

const { instance } = await WebAssembly.instantiate(await readFile(path.join(ROOT, "_build/wasm-gc/release/build/viewshed_worker/viewshed_worker.wasm")), { Math });
const v = instance.exports;
// As the analysis worker calls it: only the window of cells the viewshed reads goes in.
const ours = (o) => {
  const args = [width, height, 0, res, 0, 0, 0, -res, o.x, o.y, o.oz, o.tz, o.md, o.cc, 6378137, ["NORMAL", "DEM", "GROUND"].indexOf(o.om), 255, 0, 0];
  let count = v.viewshed_window(...args);
  if (count < 0) return { error: new TextDecoder().decode(new Uint8Array(v.memory.buffer, v.output_addr(), -count)) };
  const [wx, wy, ww, wh] = new Int32Array(v.memory.buffer.slice(v.output_addr(), v.output_addr() + 16));
  const cut = new Float64Array(ww * wh);
  for (let y = 0; y < wh; y++) cut.set(elev.subarray((wy + y) * width + wx, (wy + y) * width + wx + ww), y * ww);
  const bytes = new Uint8Array(cut.buffer);
  const p = v.prepare_input(bytes.length);
  new Uint8Array(v.memory.buffer, p, bytes.length).set(bytes);
  count = v.viewshed(...args, wx, wy, ww, wh);
  if (count < 0) return { error: new TextDecoder().decode(new Uint8Array(v.memory.buffer, v.output_addr(), -count)) };
  const out = new Float64Array(v.memory.buffer, v.output_addr(), count).slice();
  return { width: out[0], height: out[1], geotransform: Array.from(out.subarray(2, 8)), values: out.subarray(8) };
};
// gdal_viewshed's output, read back through an ASCII grid with every digit.
function theirs(o) {
  const out = path.join(dir, "out.tif");
  execFileSync("gdal_viewshed", ["-q", "-b", "1", "-ox", String(o.x), "-oy", String(o.y), "-oz", String(o.oz), "-tz", String(o.tz), "-md", String(o.md), "-cc", String(o.cc),
    "-vv", "255", "-iv", "0", "-ov", "0", "-om", o.om, "-of", "GTiff", tif, out]);
  const asc = path.join(dir, "out.asc");
  execFileSync("gdal_translate", ["-q", "-of", "AAIGrid", "-co", "SIGNIFICANT_DIGITS=17", out, asc]);
  const text = readFileSync(asc, "utf8").trim().split("\n");
  const header = {};
  while (/^[a-z]/i.test(text[0])) {
    const [k, val] = text.shift().trim().split(/\s+/);
    header[k.toLowerCase()] = Number(val);
  }
  const values = Float64Array.from(text.flatMap((l) => l.trim().split(/\s+/).map(Number)));
  const cell = header.cellsize ?? header.dx;
  return { width: header.ncols, height: header.nrows, geotransform: [header.xllcorner, cell, 0, header.yllcorner + header.nrows * (header.cellsize ?? header.dy), 0, -(header.cellsize ?? header.dy)], values };
}

// Observers: the summit (the grid's highest cell), a slope, a valley cell and the grid's edge.
let top = 0;
for (let i = 1; i < elev.length; i++) if (elev[i] > elev[top]) top = i;
const cellAt = (col, row) => ({ x: (col + 0.5) * res, y: -(row + 0.5) * res });
const observers = { summit: cellAt(top % width, Math.floor(top / width)), slope: cellAt(Math.floor(width * 0.45), Math.floor(height * 0.55)), valley: cellAt(Math.floor(width * 0.8), Math.floor(height * 0.2)), edge: cellAt(0, Math.floor(height / 2)) };
const results = {};
const failures = [];
for (const [where, xy] of Object.entries(observers)) {
  for (const om of ["NORMAL", "DEM", "GROUND"]) {
    for (const [oz, tz, md, cc] of [[2, 0, 0, 0.85714], [50, 10, 5000, 0.85714], [2, 0, 20000, 0]]) {
      const o = { ...xy, oz, tz, md, cc, om };
      const [want, got] = [theirs(o), ours(o)];
      const r = (results[`${where} ${om}`] ??= { cases: 0, identical: 0, cells: 0, differ: 0 });
      r.cases++;
      let differ = got.error ? want.values.length : 0;
      const sameShape = !got.error && want.width === got.width && want.height === got.height && want.geotransform.every((g, k) => Math.abs(g - got.geotransform[k]) <= 1e-6 * Math.max(1, Math.abs(g)));
      const sample = [];
      if (sameShape) {
        for (let k = 0; k < want.values.length; k++) {
          if (Object.is(want.values[k], got.values[k])) continue;
          differ++;
          if (sample.length < 3) sample.push([k, want.values[k], got.values[k]]);
        }
      }
      r.cells += want.values.length;
      r.differ += sameShape ? differ : want.values.length;
      if (sameShape && differ === 0) r.identical++;
      else if (failures.length < 20) failures.push({ where, o, size: [want.width, want.height, got.width, got.height], geotransform: [want.geotransform, got.geotransform], differ, sample, error: got.error });
    }
  }
}
console.log(version);
console.table(results);
for (const f of failures.slice(0, 10)) console.log(JSON.stringify(f));
const ok = failures.length === 0;
await writeFile(path.join(ROOT, "bench/results/viewshed-golden.json"), JSON.stringify({ gdal: version, results, failures, ok }, null, 2) + "\n");
console.log(ok ? "all identical" : `${failures.length} differ`);
process.exit(ok ? 0 : 1);
