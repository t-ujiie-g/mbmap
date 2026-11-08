// Glue around the wasm-gc build of `analysis_worker`; messages are in
// docs/FORMATS.md ("Analysis worker messages").

import { hostNumber, hostText, MAX_INPUT_BYTES, writeInput } from "../../wasmio/js/host.mjs";
import { readCapped } from "../../worker/js/body.mjs";
import { checkImageSize, decodeImage } from "../../worker/js/imagesize.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";

const decoder = new TextDecoder();
const encoder = new TextEncoder();
let wasm = null;
let ready = null;
// The other modules (each name's *_worker), instantiated on first use from the URLs `init` gives.
const modules = {
  geometry: { url: null, exports: null, imports: {} },
  relate: { url: null, exports: null, imports: {} },
  shapes: { url: null, exports: null, imports: { Math } },
  surface: { url: null, exports: null, imports: { Math, host: hostText() } },
  viewshed: { url: null, exports: null, imports: { Math } },
  route: { url: null, exports: null, imports: { Math } },
  proj: { url: null, exports: null, imports: { Math } },
};
// The datasets [a, b] whose tables relate.wasm keeps from the last call.
let relateKept = null;
// Calls run one after another, after init, in the order they came.
let queue = Promise.resolve();

const input = (bytes) => writeInput(wasm, [bytes]);

// Bytes from `exports`' output area after a call that returned `n`.
function outputOf(exports, n) {
  const at = exports.output_addr();
  return new Uint8Array(exports.memory.buffer.slice(at, at + n));
}

// The result of an export that returns a count, or -2 / minus a message length (-1 in this module).
function checked(exports, n) {
  if (n < 0) throw new Error(n === -2 ? "out of memory" : n === -1 && exports === wasm ? "unknown dataset or invalid arguments" : decoder.decode(outputOf(exports, -n)));
  return n;
}
const counted = (n) => checked(wasm, n);
const f64sOf = (exports, n) => new Float64Array(outputOf(exports, checked(exports, n) * 8).buffer);
const i32sOf = (exports, n) => new Int32Array(outputOf(exports, checked(exports, n) * 4).buffer);
const f64s = (n) => f64sOf(wasm, n);
const i32s = (n) => i32sOf(wasm, n);
const tableOf = (id) => outputOf(wasm, counted(wasm.table_out(id)));
const datasetOf = (id) => ({ dataset: id, features: wasm.feature_count(id) });
// Table bytes kept as a new dataset.
function stored(bytes) {
  input(bytes);
  return datasetOf(counted(wasm.load_table()));
}
// Module `name` with the tables of datasets `ids`, then `rest`, as its input.
async function withTables(name, ids, rest = []) {
  const exports = await module(name);
  const tables = ids.map(tableOf);
  writeInput(exports, [...tables, ...rest]);
  return { exports, tables };
}

const isId = (v) => Number.isInteger(v) && v >= 0;
// The exports of shapes_worker that give a table.
const SHAPE_OPS = ["simplify", "convex", "concave", "delaunay", "voronoi", "line_slice"];
// The exports of surface_worker: those giving a table, then those giving f64s.
const SURFACE_TABLES = ["point_grid", "square_grid", "hex_grid", "triangle_grid", "interpolate", "isolines", "isobands", "density"];
const SURFACE_VALUES = ["dbscan", "kmeans"];
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
  if (isLonLat(crs)) return datasetOf(dataset);
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
// Each grid's width and height in cells, for `viewshed`.
const gridSizes = new Map();
// Each DEM grid's zoom, north-west tile and tile size (`tile`, for `gridSample`) and meters per cell (`res`).
const demTiles = new Map();
// Web Mercator tile coordinates (fractional) of a place at `n` tiles a side, and back.
function tileXY(lng, lat, n) {
  const s = Math.sin((Math.max(-85.0511, Math.min(85.0511, lat)) * Math.PI) / 180);
  return [((lng + 180) / 360) * n, (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * n];
}
const lngLatOf = (x, y, n) => [(x / n) * 360 - 180, (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / n))) * 180) / Math.PI];
// Fetches the DEM tiles of `url` (a {z}/{x}/{y} template) at zoom `z` covering
// `bounds` [west, south, east, north] and mosaics them; missing tiles are 0 m.
async function loadDem({ url, z, bounds, encoding }) {
  check(typeof url === "string" && Number.isInteger(z) && z >= 0 && z <= 24 && isBox(bounds));
  check(Array.isArray(encoding) && encoding.length === 5 && encoding.every(Number.isFinite));
  const n = 2 ** z;
  const [x0, y0, x1, y1] = [...tileXY(bounds[0], bounds[3], n), ...tileXY(bounds[2], bounds[1], n)].map((v) => Math.min(n - 1, Math.max(0, Math.floor(v))));
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
  gridSizes.set(grid, { width, height });
  demTiles.set(grid, { tile: [z, x0, y0, size], res });
  return { grid, width, height, bounds: [...lngLatOf(x0, y1 + 1, n), ...lngLatOf(x1 + 1, y0, n)] };
}

// A failed instantiation is forgotten, so a later call tries again.
function module(name) {
  const m = modules[name];
  if (!m.exports) {
    check(typeof m.url === "string");
    m.exports = WebAssembly.instantiateStreaming(fetch(m.url), m.imports).then(({ instance }) => instance.exports, (err) => {
      m.exports = null;
      throw err;
    });
  }
  return m.exports;
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

// Runs `call` in the geometry module on datasets `ids` and keeps its result as a new dataset.
async function geometryOp(ids, call, name = "geometry") {
  const { exports, tables } = await withTables(name, ids);
  return stored(outputOf(exports, checked(exports, call(exports, tables[0].length))));
}

// Dataset `dataset` taken from CRS `from` to CRS `to` (module ids), as a new
// dataset: its coordinates go through the coordinate system module.
async function reproject(dataset, from, to) {
  const proj = await module("proj");
  const n = counted(wasm.coords_out(dataset));
  writeInput(proj, [outputOf(wasm, n * 8)]);
  input(outputOf(proj, checked(proj, proj.transform_coords(from, to)) * 8));
  return datasetOf(counted(wasm.with_coords(dataset)));
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
  gridSizes.set(grid, { width, height });
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
    return outputOf(wasm, counted(wasm.grid_hillshade(grid, azimuth, altitude, zFactor)));
  },
  // GDAL's viewshed of a grid (viewshed_worker), in its own file loaded with the first one.
  async viewshed({ grid, observer, options }) {
    check((demTiles.has(grid) || rasterGrids.has(grid)) && Array.isArray(observer) && observer.length === 2 && observer.every(Number.isFinite));
    const cells = (x, y, w, h) => f64s(wasm.grid_window(grid, x, y, w, h));
    const { viewshed } = await import("./viewshed.mjs");
    return viewshed({
      cells, size: gridSizes.get(grid), dem: demTiles.get(grid), raster: rasterGrids.get(grid), observer, options,
      check, checked, writeInput, f64sOf, module, crsId, transform: OPS.transform, tileXY, lngLatOf,
    });
  },
  // geojson-path-finder's graph of a dataset's lines, kept by handle in route_worker.
  async network({ dataset, tolerance }) {
    check(isId(dataset) && tolerance > 0 && Number.isFinite(tolerance));
    const { exports } = await withTables("route", [dataset]);
    return checked(exports, exports.network_new(tolerance));
  },
  // The shortest path of `network` between two points on it: weight (km), then x, y pairs; empty for none.
  async route({ network, from, to }) {
    check(isId(network) && [...from, ...to].every(Number.isFinite) && from.length === 2 && to.length === 2);
    const exports = await module("route");
    return f64sOf(exports, exports.network_path(network, ...from, ...to));
  },
  async disposeNetwork({ network }) {
    check(isId(network));
    (await module("route")).network_dispose(network);
    return null;
  },
  dispose({ dataset }) {
    check(isId(dataset));
    wasm.dispose(dataset);
    if (relateKept?.includes(dataset)) {
      relateKept = null;
      modules.relate.exports.forget_tables();
    }
    demTiles.delete(dataset);
    gridSizes.delete(dataset);
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
    return f64s(wasm.grid_sample(grid, ...demTiles.get(grid).tile));
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
    // relate.wasm keeps the last pair's tables (len_a -1 reuses them): datasets never change and ids are not reused.
    let exports, lenA;
    if (relateKept?.[0] === a && relateKept[1] === b) [exports, lenA] = [await module("relate"), -1];
    else {
      const w = await withTables("relate", [a, b]);
      [exports, lenA] = [w.exports, w.tables[0].length];
    }
    relateKept = null;
    const n = pair ? exports.relate_matrix(lenA, ...pair) : exports.relate_pairs(lenA, predicate, pattern);
    if (n >= 0) relateKept = [a, b];
    if (pair) return decoder.decode(outputOf(exports, checked(exports, n)));
    return i32sOf(exports, n);
  },
  // A shape operation of shapes_worker on one dataset: `shape` an export giving a table, with `args` numbers.
  shapes({ dataset, shape, args }) {
    check(isId(dataset) && SHAPE_OPS.includes(shape) && Array.isArray(args) && args.every((v) => typeof v === "number"));
    return geometryOp([dataset], (s) => s[shape](...args), "shapes");
  },
  // Per feature of `dataset`, the point of its lines nearest to (x, y) as Turf's nearestPointOnLine: 6 f64s.
  async nearestOnLine({ dataset, x, y }) {
    check(isId(dataset) && Number.isFinite(x) && Number.isFinite(y));
    const { exports } = await withTables("shapes", [dataset]);
    return f64sOf(exports, exports.nearest_on_line(x, y));
  },
  // A surface_worker export `fn` over `dataset` (-1 for none) with `args` numbers; its input is the
  // dataset's table, then `text` (a property name) as UTF-8, then `numbers` as f64s. A table result
  // becomes a new dataset; the f64s of dbscan and kmeans are returned as they are.
  async surface({ dataset, fn, args, text = "", numbers = [] }) {
    const values = SURFACE_VALUES.includes(fn);
    check((dataset === -1 || isId(dataset)) && (values || SURFACE_TABLES.includes(fn)) && typeof text === "string");
    check([args, numbers].every((a) => Array.isArray(a) && a.every((v) => typeof v === "number")));
    const name = encoder.encode(text);
    const { exports, tables } = await withTables("surface", dataset === -1 ? [] : [dataset], [name, new Uint8Array(Float64Array.from(numbers).buffer)]);
    const n = exports[fn](tables[0]?.length ?? 0, name.length, ...args);
    return values ? f64sOf(exports, n) : stored(outputOf(exports, checked(exports, n)));
  },
  overlay({ a, b, kind }) {
    check(isId(a) && isId(b) && [0, 1, 2, 3].includes(kind));
    return geometryOp([a, b], (g, lenA) => g.overlay(lenA, kind));
  },
  async toGeoJSON({ dataset, crs }) {
    check(isId(dataset) && (crs === undefined || isCrs(crs)));
    if (isLonLat(crs)) return tableToGeoJSON(tableOf(dataset));
    const { dataset: projected } = await reproject(dataset, 4326, await crsId(crs));
    try {
      return tableToGeoJSON(tableOf(projected));
    } finally {
      wasm.dispose(projected);
    }
  },
  async transform({ coords, from, to }) {
    check(coords instanceof ArrayBuffer && coords.byteLength % 16 === 0 && isCrs(from) && isCrs(to));
    const [f, t] = [await crsId(from), await crsId(to)];
    const proj = await module("proj");
    writeInput(proj, [new Uint8Array(coords)]);
    return f64sOf(proj, proj.transform_coords(f, t));
  },
  grid({ dataset, bbox, cols, rows }) {
    check(isId(dataset) && isBox(bbox) && Number.isInteger(cols) && Number.isInteger(rows));
    return i32s(wasm.grid(dataset, ...bbox, cols, rows));
  },
};

async function run(msg) {
  if (!ready || !Object.hasOwn(OPS, msg.op)) throw new Error("unknown call");
  await ready;
  const value = await OPS[msg.op](msg);
  const transfer = ArrayBuffer.isView(value) ? [value.buffer] : [];
  postMessage({ type: "result", id: msg.id, value }, transfer);
}

onmessage = (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready && typeof msg.wasm === "string") {
    for (const name in modules) modules[name].url = typeof msg[name] === "string" ? msg[name] : null;
    const host = { number: hostNumber(() => wasm.memory) };
    ready = WebAssembly.instantiateStreaming(fetch(msg.wasm), { Math, host })
      .then(({ instance }) => { wasm = instance.exports; });
  } else if (msg?.type === "call" && Number.isInteger(msg.id)) {
    queue = queue.then(() => run(msg)).catch((err) => {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    });
  }
};
