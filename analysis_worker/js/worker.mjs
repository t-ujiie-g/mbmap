// Glue around the wasm-gc build of `analysis_worker`; messages are in
// docs/FORMATS.md ("Analysis worker messages").

import { hostNumber } from "../../wasmio/js/host.mjs";

const decoder = new TextDecoder();
const encoder = new TextEncoder();
let wasm = null;
let ready = null;
// Calls run one after another, after init, in the order they came.
let queue = Promise.resolve();

function input(bytes) {
  const addr = wasm.prepare_input(bytes.length);
  if (addr < 0) throw new Error(`input too large (${bytes.length} bytes)`);
  new Uint8Array(wasm.memory.buffer, addr, bytes.length).set(bytes);
}

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
const isBox = (b) => Array.isArray(b) && b.length === 4 && b.every(Number.isFinite);
function check(ok) {
  if (!ok) throw new Error("invalid arguments");
}

async function load({ url, bytes }) {
  let data = bytes instanceof ArrayBuffer ? new Uint8Array(bytes) : null;
  if (!data) {
    check(typeof url === "string" && /^https?:/.test(url));
    const res = await fetch(url, { credentials: "omit" });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    data = new Uint8Array(await res.arrayBuffer());
  }
  input(data);
  const dataset = counted(wasm.load());
  return { dataset, features: wasm.feature_count(dataset) };
}

// Fetches the DEM tiles of `url` (a {z}/{x}/{y} template) at zoom `z` covering
// `bounds` [west, south, east, north] and mosaics them; missing tiles are 0 m.
const WORLD_WIDTH = 40075016.6855785;
const MAX_GRID_SIDE = 4096; // analysis_worker/dem.mbt
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
  const tiles = [];
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) tiles.push({ x, y, href: url.replace("{z}", z).replace("{x}", x).replace("{y}", y) });
  check(tiles.every((t) => /^https?:/.test(t.href)));
  const images = await Promise.all(tiles.map(async (t) => {
    const res = await fetch(t.href, { credentials: "omit" });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${t.href}`);
    return createImageBitmap(await res.blob(), { premultiplyAlpha: "none", colorSpaceConversion: "none" });
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
  const lng = (x) => (x / n) * 360 - 180;
  const latOf = (y) => (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / n))) * 180) / Math.PI;
  return { grid, width, height, bounds: [lng(x0), latOf(y1 + 1), lng(x1 + 1), latOf(y0)] };
}

const OPS = {
  load,
  loadDem,
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
    return null;
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
    const host = { number: hostNumber(() => wasm.memory) };
    ready = WebAssembly.instantiateStreaming(fetch(msg.wasm), { Math: { sin: Math.sin, cos: Math.cos, atan2: Math.atan2 }, host })
      .then(({ instance }) => { wasm = instance.exports; });
  } else if (msg?.type === "call" && ready && Number.isInteger(msg.id) && Object.hasOwn(OPS, msg.op)) {
    queue = queue.then(() => run(msg)).catch((err) => {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    });
  }
};
