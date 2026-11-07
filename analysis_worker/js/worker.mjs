// Glue around the wasm-gc build of `analysis_worker`; messages are in
// docs/FORMATS.md ("Analysis worker messages").

import { hostNumber, MAX_INPUT_BYTES, writeInput } from "../../wasmio/js/host.mjs";
import { readCapped } from "../../worker/js/body.mjs";
import { checkImageSize, decodeImage } from "../../worker/js/imagesize.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";

const decoder = new TextDecoder();
const encoder = new TextEncoder();
let wasm = null;
let ready = null;
// The geometry (geometry_worker), spatial relation (relate_worker), shape
// (shapes_worker) and coordinate system (proj_worker) modules, each instantiated
// on its first use. shapes_worker and proj_worker compute with the host's Math,
// as Turf and proj4js do.
const modules = {
  geometry: { url: null, exports: null, imports: {} },
  relate: { url: null, exports: null, imports: {} },
  shapes: { url: null, exports: null, imports: { Math } },
  proj: { url: null, exports: null, imports: { Math } },
};
// Calls run one after another, after init, in the order they came.
let queue = Promise.resolve();

const input = (bytes) => writeInput(wasm, [bytes]);

// The result of an export that returns a count, or -1 / -2 / minus a message length.
function counted(n) {
  if (n === -1) throw new Error("unknown dataset or invalid arguments");
  if (n === -2) throw new Error("out of memory");
  if (n < 0) throw new Error(decoder.decode(new Uint8Array(wasm.memory.buffer, wasm.output_addr(), -n)));
  return n;
}

const f64s = (n) => {
  const at = wasm.output_addr();
  return new Float64Array(wasm.memory.buffer.slice(at, at + counted(n) * 8));
};
const i32s = (n) => {
  const at = wasm.output_addr();
  return new Int32Array(wasm.memory.buffer.slice(at, at + counted(n) * 4));
};

const isId = (v) => Number.isInteger(v) && v >= 0;
// The exports of shapes_worker that give a table.
const SHAPE_OPS = ["simplify", "convex", "concave", "delaunay", "voronoi", "line_slice"];
// `@proj.DEFINITION_SLOTS` (proj/encoding.mbt).
const DEFINITION_SLOTS = 34;
// An EPSG code, or a definition as docs/FORMATS.md "CRS definition" encodes it.
const isCrs = (c) => (Number.isInteger(c) && c > 0) || (c instanceof Float64Array && c.length === DEFINITION_SLOTS);
const isLonLat = (c) => c === undefined || c === 4326;
const isBox = (b) => Array.isArray(b) && b.length === 4 && b.every(Number.isFinite);
function check(ok) {
  if (!ok) throw new Error("invalid arguments");
}

async function load({ url, bytes, table, crs }) {
  let data = bytes instanceof ArrayBuffer ? new Uint8Array(bytes) : table instanceof ArrayBuffer ? new Uint8Array(table) : null;
  if (!data) {
    check(typeof url === "string" && /^https?:/.test(url));
    const res = await fetch(url, { credentials: "omit" });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    data = await readCapped(res, MAX_INPUT_BYTES);
  }
  input(data);
  const dataset = counted(table instanceof ArrayBuffer ? wasm.load_table() : wasm.load());
  if (isLonLat(crs)) return { dataset, features: wasm.feature_count(dataset) };
  // Coordinates in another CRS: kept as longitude and latitude.
  try {
    check(isCrs(crs));
    return await reproject(dataset, await crsId(crs), 4326);
  } finally {
    wasm.dispose(dataset);
  }
}

const WORLD_WIDTH = 40075016.6855785;
const MAX_GRID_SIDE = 4096; // analysis_worker/dem.mbt
// Each DEM grid's zoom, north-west tile and tile size, for `gridSample`.
const demTiles = new Map();
// Fetches the DEM tiles of `url` (a {z}/{x}/{y} template) at zoom `z` covering
// `bounds` [west, south, east, north] and mosaics them; missing tiles are 0 m.
async function loadDem({ url, z, bounds, encoding }) {
  check(typeof url === "string" && Number.isInteger(z) && z >= 0 && z <= 24 && isBox(bounds));
  check(Array.isArray(encoding) && encoding.length === 5 && encoding.every(Number.isFinite));
  const n = 2 ** z;
  const tx = (lng) => Math.min(n - 1, Math.max(0, Math.floor(((lng + 180) / 360) * n)));
  const ty = (lat) => {
    const s = Math.sin((Math.max(-85.0511, Math.min(85.0511, lat)) * Math.PI) / 180);
    return Math.min(n - 1, Math.max(0, Math.floor((0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * n)));
  };
  const [x0, x1, y0, y1] = [tx(bounds[0]), tx(bounds[2]), ty(bounds[3]), ty(bounds[1])];
  // Checked before any fetch: tiles are at least 256 px, so a grid takes at most 16 a side.
  const most = MAX_GRID_SIDE / 256;
  if (x1 - x0 + 1 > most || y1 - y0 + 1 > most) throw new Error(`${(x1 - x0 + 1) * (y1 - y0 + 1)} DEM tiles at zoom ${z} are too many for one grid`);
  const tiles = [];
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) tiles.push({ x, y, href: url.replace("{z}", z).replace("{x}", x).replace("{y}", y) });
  check(tiles.every((t) => /^https?:/.test(t.href)));
  const images = await Promise.all(tiles.map(async (t) => {
    const res = await fetch(t.href, { credentials: "omit" });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${t.href}`);
    const bytes = await readCapped(res);
    checkImageSize(bytes, MAX_GRID_SIDE, `DEM tile ${t.href}`);
    return decodeImage(new Blob([bytes]));
  }));
  const size = images.find((i) => i)?.width ?? 256;
  const [width, height] = [(x1 - x0 + 1) * size, (y1 - y0 + 1) * size];
  if (width > MAX_GRID_SIDE || height > MAX_GRID_SIDE) throw new Error(`a DEM grid of ${width} x ${height} cells is too large`);
  const canvas = new OffscreenCanvas(width, height);
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  tiles.forEach((t, i) => {
    if (images[i]) ctx.drawImage(images[i], (t.x - x0) * size, (t.y - y0) * size);
    images[i]?.close();
  });
  input(new Uint8Array(ctx.getImageData(0, 0, width, height).data.buffer));
  // Ground meters per cell at the grid's middle latitude (Web Mercator pixels shrink by its cosine).
  const lat = Math.atan(Math.sinh(Math.PI * (1 - ((y0 + y1 + 1) / 2) * (2 / n))));
  const res = (WORLD_WIDTH / n / size) * Math.cos(lat);
  const grid = counted(wasm.load_dem(width, height, ...encoding, res, res));
  demTiles.set(grid, [z, x0, y0, size]);
  const lng = (x) => (x / n) * 360 - 180;
  const latOf = (y) => (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / n))) * 180) / Math.PI;
  return { grid, width, height, bounds: [lng(x0), latOf(y1 + 1), lng(x1 + 1), latOf(y0)] };
}

// Bytes from `exports`' output area after a call that returned `n`.
function outputOf(exports, n) {
  const at = exports.output_addr();
  return new Uint8Array(exports.memory.buffer.slice(at, at + n));
}

function module(name) {
  const m = modules[name];
  if (!m.exports) {
    check(typeof m.url === "string");
    m.exports = WebAssembly.instantiateStreaming(fetch(m.url), m.imports).then(({ instance }) => instance.exports);
  }
  return m.exports;
}

function checked(exports, n) {
  if (n < 0) throw new Error(n === -2 ? "out of memory" : decoder.decode(outputOf(exports, -n)));
  return n;
}

// The coordinate system module's id for `crs`: an EPSG code as it is, a
// definition made there once (handle h is -1 - h).
const defined = new Map();
async function crsId(crs) {
  if (typeof crs === "number") return crs;
  const key = Array.from(crs).join(",");
  if (!defined.has(key)) {
    const proj = await module("proj");
    writeInput(proj, [new Uint8Array(crs.buffer, crs.byteOffset, crs.byteLength)]);
    defined.set(key, -1 - checked(proj, proj.define_crs()));
  }
  return defined.get(key);
}

// Runs `call` in the geometry module on `tables` (datasets, in Table bytes)
// and keeps its result as a new dataset.
async function geometryOp(tables, call, name = "geometry") {
  const exports = await module(name);
  const bytes = tables.map((id) => outputOf(wasm, counted(wasm.table_out(id))));
  writeInput(exports, bytes);
  input(outputOf(exports, checked(exports, call(exports, bytes[0].length))));
  const dataset = counted(wasm.load_table());
  return { dataset, features: wasm.feature_count(dataset) };
}

// Dataset `dataset` taken from CRS `from` to CRS `to` (module ids), as a new
// dataset: its coordinates go through the coordinate system module.
async function reproject(dataset, from, to) {
  const proj = await module("proj");
  const n = counted(wasm.coords_out(dataset));
  writeInput(proj, [outputOf(wasm, n * 8)]);
  input(outputOf(proj, checked(proj, proj.transform_coords(from, to)) * 8));
  const id = counted(wasm.with_coords(dataset));
  return { dataset: id, features: wasm.feature_count(id) };
}

// Each GeoTIFF grid's north-west corner, cell step (x, y; y negative north up) and CRS, for `gridSample`.
const rasterGrids = new Map();
// A band (f64s, NaN for no data) as a grid of `res` cells; `bbox` [x0, y0, x1, y1] in `crs`
// (an EPSG code, 4326 by default), its corners taken to longitude and latitude for `bounds`.
async function loadGrid({ values, width, height, res, origin, step, crs = 4326 }) {
  check(values instanceof ArrayBuffer && Number.isInteger(width) && Number.isInteger(height) && values.byteLength === width * height * 8);
  check([...res, ...origin, ...step].every(Number.isFinite) && res.length === 2 && origin.length === 2 && step.length === 2 && isCrs(crs));
  if (width > MAX_GRID_SIDE || height > MAX_GRID_SIDE) throw new Error(`a grid of ${width} x ${height} cells is too large`);
  input(new Uint8Array(values));
  const grid = counted(wasm.load_grid(width, height, res[0], res[1]));
  rasterGrids.set(grid, { origin, step, crs });
  const corners = new Float64Array([0, 0, width, 0, 0, height, width, height].map((v, i) => origin[i % 2] + v * step[i % 2]));
  const ll = crs === 4326 ? corners : await OPS.transform({ coords: corners.buffer, from: crs, to: 4326 });
  const xs = [ll[0], ll[2], ll[4], ll[6]];
  const ys = [ll[1], ll[3], ll[5], ll[7]];
  return { grid, width, height, bounds: [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)] };
}

const OPS = {
  load,
  loadDem,
  loadGrid,
  gridValues({ grid, kind }) {
    check(isId(grid) && Number.isInteger(kind));
    return f64s(wasm.grid_values(grid, kind));
  },
  gridHillshade({ grid, azimuth, altitude, zFactor }) {
    check(isId(grid) && [azimuth, altitude, zFactor].every(Number.isFinite));
    const n = counted(wasm.grid_hillshade(grid, azimuth, altitude, zFactor));
    const at = wasm.output_addr();
    return new Uint8Array(wasm.memory.buffer.slice(at, at + n));
  },
  dispose({ dataset }) {
    check(isId(dataset));
    wasm.dispose(dataset);
    demTiles.delete(dataset);
    rasterGrids.delete(dataset);
    return null;
  },
  async gridSample({ grid, coords }) {
    check((demTiles.has(grid) || rasterGrids.has(grid)) && coords instanceof ArrayBuffer && coords.byteLength % 16 === 0);
    const raster = rasterGrids.get(grid);
    if (raster) {
      // Longitude and latitude to the grid's CRS, then to pixels from its north-west corner.
      const { origin, step, crs } = raster;
      const xy = new Float64Array(crs === 4326 ? coords : await OPS.transform({ coords, from: 4326, to: crs }));
      for (let i = 0; i < xy.length; i += 2) {
        xy[i] = (xy[i] - origin[0]) / step[0];
        xy[i + 1] = (xy[i + 1] - origin[1]) / step[1];
      }
      input(new Uint8Array(xy.buffer));
      return f64s(wasm.grid_sample_pixels(grid));
    }
    input(new Uint8Array(coords));
    return f64s(wasm.grid_sample(grid, ...demTiles.get(grid)));
  },
  measure({ dataset, kind }) {
    check(isId(dataset) && Number.isInteger(kind));
    return f64s(wasm.measure(dataset, kind));
  },
  search({ dataset, bbox }) {
    check(isId(dataset) && isBox(bbox));
    return i32s(wasm.search(dataset, ...bbox));
  },
  nearest({ dataset, x, y, k, maxDistance }) {
    check(isId(dataset) && Number.isFinite(x) && Number.isFinite(y) && Number.isInteger(k) && k >= 0 && k <= 0x7fffffff && maxDistance >= 0);
    return i32s(wasm.nearest(dataset, x, y, k, maxDistance));
  },
  within({ points, polygons }) {
    check(isId(points) && isId(polygons));
    return i32s(wasm.within(points, polygons));
  },
  collect({ polygons, points, property }) {
    check(isId(polygons) && isId(points) && typeof property === "string");
    input(encoder.encode(property));
    return f64s(wasm.collect(polygons, points));
  },
  async buffer({ dataset, meters, mode, join, cap, arcTolerance, crs }) {
    check(isId(dataset) && Number.isFinite(meters) && [mode, join, cap].every(Number.isInteger) && arcTolerance >= 0 && isCrs(crs));
    const op = (id) => geometryOp([id], (g) => g.buffer(meters, mode, join, cap, arcTolerance));
    if (mode !== 1) return op(dataset);
    // Planar: in the CRS's plane, then back.
    const id = await crsId(crs);
    const proj = await module("proj");
    if (checked(proj, proj.crs_kind(id)) === 1) throw new Error("a planar buffer needs a projected CRS");
    const temps = [];
    try {
      temps.push((await reproject(dataset, 4326, id)).dataset);
      temps.push((await op(temps[0])).dataset);
      return await reproject(temps[1], id, 4326);
    } finally {
      for (const t of temps) wasm.dispose(t);
    }
  },
  dissolve({ dataset }) {
    check(isId(dataset));
    return geometryOp([dataset], (g) => g.dissolve());
  },
  merge({ dataset }) {
    check(isId(dataset));
    return geometryOp([dataset], (g) => g.merge());
  },
  // Pairs of rows of `a` and `b` in relation `predicate` (a code of relate_worker), or matching
  // a packed DE-9IM `pattern` (predicate -1); with `pair`, the matrix of rows `pair` as text.
  async relate({ a, b, predicate, pattern, pair }) {
    check(isId(a) && isId(b) && Number.isInteger(predicate) && Number.isInteger(pattern));
    check(pair === undefined || (Array.isArray(pair) && pair.length === 2 && pair.every(isId)));
    const exports = await module("relate");
    const bytes = [a, b].map((id) => outputOf(wasm, counted(wasm.table_out(id))));
    writeInput(exports, bytes);
    if (pair) return decoder.decode(outputOf(exports, checked(exports, exports.relate_matrix(bytes[0].length, ...pair))));
    const n = checked(exports, exports.relate_pairs(bytes[0].length, predicate, pattern));
    return new Int32Array(outputOf(exports, n * 4).buffer);
  },
  // A shape operation of shapes_worker on one dataset: `op` an export giving a table, with `args` numbers.
  shapes({ dataset, op, args }) {
    check(isId(dataset) && SHAPE_OPS.includes(op) && Array.isArray(args) && args.every((v) => typeof v === "number"));
    return geometryOp([dataset], (s) => s[op](...args), "shapes");
  },
  // Per feature of `dataset`, the point of its lines nearest to (x, y) as Turf's nearestPointOnLine: 6 f64s.
  async nearestOnLine({ dataset, x, y }) {
    check(isId(dataset) && Number.isFinite(x) && Number.isFinite(y));
    const exports = await module("shapes");
    writeInput(exports, [outputOf(wasm, counted(wasm.table_out(dataset)))]);
    return new Float64Array(outputOf(exports, checked(exports, exports.nearest_on_line(x, y)) * 8).buffer);
  },
  overlay({ a, b, kind }) {
    check(isId(a) && isId(b) && [0, 1, 2, 3].includes(kind));
    return geometryOp([a, b], (g, lenA) => g.overlay(lenA, kind));
  },
  async toGeoJSON({ dataset, crs }) {
    check(isId(dataset) && (crs === undefined || isCrs(crs)));
    if (isLonLat(crs)) return tableToGeoJSON(outputOf(wasm, counted(wasm.table_out(dataset))));
    const { dataset: projected } = await reproject(dataset, 4326, await crsId(crs));
    try {
      return tableToGeoJSON(outputOf(wasm, counted(wasm.table_out(projected))));
    } finally {
      wasm.dispose(projected);
    }
  },
  async transform({ coords, from, to }) {
    check(coords instanceof ArrayBuffer && coords.byteLength % 16 === 0 && isCrs(from) && isCrs(to));
    const [f, t] = [await crsId(from), await crsId(to)];
    const proj = await module("proj");
    writeInput(proj, [new Uint8Array(coords)]);
    return new Float64Array(outputOf(proj, checked(proj, proj.transform_coords(f, t)) * 8).buffer);
  },
  grid({ dataset, bbox, cols, rows }) {
    check(isId(dataset) && isBox(bbox) && Number.isInteger(cols) && Number.isInteger(rows));
    return i32s(wasm.grid(dataset, ...bbox, cols, rows));
  },
};

async function run(msg) {
  await ready;
  const value = await OPS[msg.op](msg);
  const transfer = ArrayBuffer.isView(value) ? [value.buffer] : [];
  postMessage({ type: "result", id: msg.id, value }, transfer);
}

onmessage = (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready && typeof msg.wasm === "string") {
    modules.geometry.url = typeof msg.geometry === "string" ? msg.geometry : null;
    modules.relate.url = typeof msg.relate === "string" ? msg.relate : null;
    modules.shapes.url = typeof msg.shapes === "string" ? msg.shapes : null;
    modules.proj.url = typeof msg.proj === "string" ? msg.proj : null;
    const host = { number: hostNumber(() => wasm.memory) };
    ready = WebAssembly.instantiateStreaming(fetch(msg.wasm), { Math, host })
      .then(({ instance }) => { wasm = instance.exports; });
  } else if (msg?.type === "call" && ready && Number.isInteger(msg.id) && Object.hasOwn(OPS, msg.op)) {
    queue = queue.then(() => run(msg)).catch((err) => {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    });
  }
};
