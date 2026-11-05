// Slope, aspect and hillshade of the analysis wasm vs gdaldem (Horn) on the Mt Fuji DEM (interior
// cells: gdaldem leaves borders empty), and sampling vs gdallocationinfo -r bilinear at lng/lat
// points. Needs GDAL on PATH. Usage: node terrain/golden.mjs
import { execFileSync, spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";
import { nodeFetchBytes } from "../lib/node-io.mjs";
import { decodePng } from "../lib/png.mjs";
import { loadAnalysis } from "../analysis/load.mjs";

const SET = { z: 12, x: [3625, 3628], y: [1616, 1619], dir: "bench/fixtures/gsi-dem-fuji" };
const SIZE = 256;
const cols = SET.x[1] - SET.x[0] + 1;
const rows = SET.y[1] - SET.y[0] + 1;
const width = cols * SIZE;
const height = rows * SIZE;

// The mosaic's RGBA, tile by tile.
const rgba = new Uint8Array(width * height * 4);
for (let ty = 0; ty < rows; ty++) {
  for (let tx = 0; tx < cols; tx++) {
    const png = decodePng(await readFile(path.join(ROOT, SET.dir, `${SET.z}/${SET.x[0] + tx}/${SET.y[0] + ty}.png`)));
    for (let y = 0; y < SIZE; y++) {
      rgba.set(png.rgba.subarray(y * SIZE * 4, (y + 1) * SIZE * 4), ((ty * SIZE + y) * width + tx * SIZE) * 4);
    }
  }
}
// Cells as wide on the ground as Web Mercator pixels at the mosaic's middle latitude.
const n = 2 ** SET.z;
const lat = Math.atan(Math.sinh(Math.PI * (1 - (2 * (SET.y[0] + rows / 2)) / n))) * 180 / Math.PI;
const res = (40075016.6855785 / n / SIZE) * Math.cos((lat * Math.PI) / 180);

const wasm = await loadAnalysis(nodeFetchBytes);
const e = wasm.exports;
const at = e.prepare_input(rgba.length);
new Uint8Array(e.memory.buffer, at, rgba.length).set(rgba);
const id = e.load_dem(width, height, 2, 0, 0, 0, 0, res, res);
if (id < 0) throw new Error("load_dem failed");
const f64s = (count) => new Float64Array(e.memory.buffer, e.output_addr(), count).slice();
const elev = f64s(e.grid_values(id, 0));
const slope = f64s(e.grid_values(id, 1));
const aspect = f64s(e.grid_values(id, 2));
const shade = new Uint8Array(e.memory.buffer, e.output_addr(), e.grid_hillshade(id, 315, 45, 1)).slice();

// The same elevations for gdaldem, as an ASCII grid (no data as 0 m, as ours).
const dir = path.join(ROOT, "bench/dist/terrain");
await mkdir(dir, { recursive: true });
const lines = [`ncols ${width}`, `nrows ${height}`, "xllcorner 0", "yllcorner 0", `cellsize ${res}`];
for (let y = 0; y < height; y++) lines.push(Array.from(elev.subarray(y * width, (y + 1) * width), (v) => (Number.isNaN(v) ? 0 : v)).join(" "));
await writeFile(path.join(dir, "dem.asc"), lines.join("\n") + "\n");
const gdal = (args, out) => {
  execFileSync("gdaldem", [...args, path.join(dir, "dem.asc"), path.join(dir, out), "-of", "AAIGrid", "-q"]);
  return readGrid(path.join(dir, out));
};
// An ASCII grid's no-data value and cells.
function readGrid(file) {
  const text = readFileSync(file, "utf8").trim().split("\n");
  const header = {};
  let i = 0;
  while (/^[a-zA-Z]/.test(text[i])) {
    const [k, v] = text[i].trim().split(/\s+/);
    header[k.toLowerCase()] = Number(v);
    i++;
  }
  const values = text.slice(i).join(" ").trim().split(/\s+/).map(Number);
  return { nodata: header.nodata_value, values };
}

let failures = 0;
// `tolerance` is a number, or per cell a function of its index.
function compare(name, ours, theirs, tolerance, skip = () => false, angle = false) {
  let worst = 0;
  let over = 0;
  let exact = 0;
  let compared = 0;
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const k = y * width + x;
      const t = theirs.values[k];
      if (t === theirs.nodata || skip(k, t)) continue;
      const raw = Math.abs(ours[k] - t);
      // Angles wrap: 359.99 and 0.01 degrees are 0.02 apart.
      const d = angle ? Math.min(raw, 360 - raw) : raw;
      compared++;
      if (d === 0) exact++;
      worst = Math.max(worst, d);
      if (d > (typeof tolerance === "function" ? tolerance(k) : tolerance)) {
        over++;
      }
    }
  }
  if (over > 0) failures++;
  const tol = typeof tolerance === "function" ? "per cell" : tolerance;
  console.log(`${name}: ${compared} cells, ${exact} exact, max difference ${worst.toPrecision(3)} (tolerance ${tol}), ${over} over`);
}
compare("slope (degrees)", slope, gdal(["slope"], "slope.asc"), 0.01);
// GDAL reads the elevations as float32 (about 2^-24 relative error), which moves
// Horn's sums by up to 8 times that and turns the aspect by atan(error / sums):
// visible where the ground is nearly flat. Cells under 0.5 degrees are left out.
const maxElev = elev.reduce((m, v) => (Number.isNaN(v) ? m : Math.max(m, Math.abs(v))), 0);
const sumError = 8 * maxElev * 2 ** -24;
const aspectTolerance = (k) => {
  const sums = 8 * res * Math.tan((slope[k] * Math.PI) / 180);
  return 0.01 + (Math.atan(sumError / sums) * 180) / Math.PI;
};
const theirAspect = gdal(["aspect"], "aspect.asc");
compare("aspect (degrees)", aspect, theirAspect, aspectTolerance, (k) => slope[k] < 0.5 || Number.isNaN(aspect[k]), true);
compare("hillshade (0-255)", shade, gdal(["hillshade"], "hillshade.asc"), 1);

// Sampling: the same grid georeferenced in Web Mercator (EPSG:3857), read as f64 by GDAL, which takes
// lng/lat to it with PROJ; ours goes through `mercator_cell`. Points inside, on the edges and outside.
{
  const WORLD = 2 * Math.PI * 6378137;
  const cell = WORLD / n / SIZE;
  const west = -WORLD / 2 + SET.x[0] * (WORLD / n);
  const north = WORLD / 2 - SET.y[0] * (WORLD / n);
  const grid = [`ncols ${width}`, `nrows ${height}`, `xllcorner ${west}`, `yllcorner ${north - height * cell}`, `cellsize ${cell}`, "NODATA_value -9999"];
  for (let y = 0; y < height; y++) grid.push(Array.from(elev.subarray(y * width, (y + 1) * width), (v) => (Number.isNaN(v) ? -9999 : v)).join(" "));
  await writeFile(path.join(dir, "dem3857.asc"), grid.join("\n") + "\n");
  const tif = path.join(dir, "dem3857.tif");
  execFileSync("gdal_translate", ["-q", "-oo", "DATATYPE=Float64", "-a_srs", "EPSG:3857", path.join(dir, "dem3857.asc"), tif]);
  const lngOf = (px) => (px / (n * SIZE)) * 360 - 180;
  const latOf = (py) => (Math.atan(Math.sinh(Math.PI * (1 - (2 * py) / (n * SIZE)))) * 180) / Math.PI;
  const [x0, y0] = [SET.x[0] * SIZE, SET.y[0] * SIZE];
  let seed = 7;
  const rand = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const points = [];
  for (let i = 0; i < 2000; i++) points.push([lngOf(x0 + rand() * width), latOf(y0 + rand() * height)]);
  for (let i = 0; i < 50; i++) points.push([lngOf(x0 + rand() * width), latOf(y0 + 0.2 * rand())], [lngOf(x0 + width - 0.2 * rand()), latOf(y0 + rand() * height)]);
  for (let i = 0; i < 20; i++) points.push([lngOf(x0 - 1 - 10 * rand()), latOf(y0 + rand() * height)]);
  // Points off the raster print an empty line and make the exit status 1.
  const theirs = spawnSync("gdallocationinfo", ["-valonly", "-r", "bilinear", "-wgs84", tif], {
    input: points.map(([lng, lat]) => `${lng} ${lat}`).join("\n") + "\n",
  }).stdout.toString().split("\n").slice(0, points.length).map((t) => (t === "" || Number(t) === -9999 ? NaN : Number(t)));
  const coords = new Float64Array(points.flat());
  const at = e.prepare_input(coords.byteLength);
  new Uint8Array(e.memory.buffer, at, coords.byteLength).set(new Uint8Array(coords.buffer));
  const ours = f64s(e.grid_sample(id, SET.z, SET.x[0], SET.y[0], SIZE));
  let worst = 0;
  let over = 0;
  let missing = 0;
  ours.forEach((v, i) => {
    if (Number.isNaN(v) !== Number.isNaN(theirs[i])) missing++;
    else if (!Number.isNaN(v)) worst = Math.max(worst, Math.abs(v - theirs[i]));
    if (!Number.isNaN(v) && Math.abs(v - theirs[i]) > 1e-6) over++;
  });
  if (over + missing > 0) failures++;
  const outside = ours.filter(Number.isNaN).length;
  console.log(`sample (m): ${points.length} points (${outside} without a value in both), max difference ${worst.toPrecision(3)} (tolerance 1e-6), ${over} over, ${missing} with a value in one only`);
}
// The same grid as a COG written by GDAL (Deflate, floating-point predictor), read by mbmap/data's
// readRaster and loaded as mbmap/analysis's loadGrid loads it: gdaldem on that file, and
// gdallocationinfo in EPSG:3857 coordinates (ours: the window's corner and resolution).
{
  const cog = path.join(dir, "dem3857-cog.tif");
  execFileSync("gdal_translate", ["-q", "-of", "COG", "-co", "COMPRESS=DEFLATE", "-co", "PREDICTOR=YES", path.join(dir, "dem3857.tif"), cog]);
  const { dataImports, dataReader, rasterSource } = await import("../../data_worker/js/read.mjs");
  const wasmOf = (name) => readFile(path.join(ROOT, `_build/wasm-gc/release/build/${name}/${name}.wasm`));
  const imports = dataImports(() => data.exports.memory);
  const data = (await WebAssembly.instantiate(await wasmOf("data_worker"), imports)).instance;
  const tiff = (await WebAssembly.instantiate(await wasmOf("geotiff_worker"), {})).instance.exports;
  const reader = dataReader(data.exports, imports, { geotiff: async () => tiff });
  const raster = await reader.readRaster(rasterSource({ bytes: new Uint8Array(readFileSync(cog)) }), {});
  if (raster.width !== width || raster.height !== height) throw new Error(`the COG reads as ${raster.width} x ${raster.height}`);
  const values = Float64Array.from(raster.bands[0], (v) => (v === raster.noData ? NaN : v));
  const [rx, ry] = raster.resolution;
  const at2 = e.prepare_input(values.byteLength);
  new Uint8Array(e.memory.buffer, at2, values.byteLength).set(new Uint8Array(values.buffer));
  const gid = e.load_grid(width, height, Math.abs(rx), Math.abs(ry));
  if (gid < 0) throw new Error("load_grid failed");
  const onCog = (args, out) => {
    execFileSync("gdaldem", [...args, cog, path.join(dir, out), "-of", "AAIGrid", "-q"]);
    return readGrid(path.join(dir, out));
  };
  compare("COG slope (degrees)", f64s(e.grid_values(gid, 1)), onCog(["slope"], "cog-slope.asc"), 0.01);
  compare("COG hillshade (0-255)", new Uint8Array(e.memory.buffer, e.output_addr(), e.grid_hillshade(gid, 315, 45, 1)).slice(), onCog(["hillshade"], "cog-hillshade.asc"), 1);
  let seed2 = 11;
  const rand2 = () => ((seed2 = (seed2 * 16807) % 2147483647) / 2147483647);
  const points = Array.from({ length: 2000 }, () => [raster.bbox[0] + rand2() * (raster.bbox[2] - raster.bbox[0]), raster.bbox[1] + rand2() * (raster.bbox[3] - raster.bbox[1])]);
  const theirs = spawnSync("gdallocationinfo", ["-valonly", "-r", "bilinear", "-geoloc", cog], {
    input: points.map(([x, y]) => `${x} ${y}`).join("\n") + "\n",
  }).stdout.toString().split("\n").slice(0, points.length).map((t) => (t === "" || Number(t) === -9999 ? NaN : Number(t)));
  const pixels = new Float64Array(points.flatMap(([x, y]) => [(x - raster.bbox[0]) / rx, (y - raster.bbox[3]) / ry]));
  const at3 = e.prepare_input(pixels.byteLength);
  new Uint8Array(e.memory.buffer, at3, pixels.byteLength).set(new Uint8Array(pixels.buffer));
  const ours = f64s(e.grid_sample_pixels(gid));
  let worst = 0;
  let over = 0;
  ours.forEach((v, i) => {
    if (Number.isNaN(v) !== Number.isNaN(theirs[i]) || (!Number.isNaN(v) && Math.abs(v - theirs[i]) > 1e-6)) over++;
    else if (!Number.isNaN(v)) worst = Math.max(worst, Math.abs(v - theirs[i]));
  });
  if (over > 0) failures++;
  console.log(`COG sample (m): ${points.length} points, max difference ${worst.toPrecision(3)} (tolerance 1e-6), ${over} over`);
}
console.log(failures === 0 ? "all within tolerance" : `${failures} comparisons out of tolerance`);
process.exit(failures === 0 ? 0 : 1);
