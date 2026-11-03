// Glue around the wasm-gc build of `worker`. Messages and the packed tile are in
// docs/FORMATS.md ("Display worker messages", "Packed tile").

import { hostText } from "../../wasmio/js/host.mjs";
import { readCapped } from "./body.mjs";
import { checkImageSize, decodeImage } from "./imagesize.mjs";
import { rangesOf, readFeatureRanges } from "./ranges.mjs";
import { readString, readValue } from "./values.mjs";

const LAYER_ENTRY_WORDS = 17; // worker/packed.mbt
const KIND_SYMBOL = 4; // worker/packed.mbt
const KIND_HILLSHADE = 5; // map/tiles.mbt
const KIND_RASTER = 7; // map/tiles.mbt
// Largest DEM tile side (worker/processor.mbt `dem_tile`) and raster tile side (JS only:
// raster tiles go to a texture without passing through the wasm).
const MAX_DEM_SIZE = 1024;
const MAX_RASTER_SIZE = 4096;
// PMTiles archives kept open at once.
const MAX_ARCHIVES = 16;
const decoder = new TextDecoder();
let wasm = null;
let ready = null;
let font = "sans-serif";
let glyphs = null;
// Without OffscreenCanvas (Safari before 16.4) labels are left out, once said.
const canDrawGlyphs = typeof OffscreenCanvas !== "undefined";
let warned = false;
const pending = new Map();
// Each tile sent, by request id, until the main thread drops it: its bytes for
// queries, and its feature ranges for layers drawn by feature state.
const kept = new Map();
// PMTiles archives by URL, their headers and directories cached.
const archives = new Map();
// The style images the main thread has, by name: [width, height, pixelRatio, sdf].
// While it is still loading a sprite, tiles wait (`imagesReady`), as MapLibre's do.
let images = new Map();
let imagesReady = Promise.resolve();
let imagesLoaded = null;

// Labels, PMTiles and queries load on first use (the npm build emits them as files next to
// this one). A failed load is forgotten, so the next tile or query tries again.
function lazy(load) {
  let p = null;
  return () => (p ??= load().catch((err) => {
    p = null;
    throw err;
  }));
}
let symbols = null;
const loadSymbols = lazy(() => import("./symbols.mjs").then((m) => {
  glyphs = new m.Glyphs(font);
  symbols = m;
}));
const loadPmtiles = lazy(() => import("./pmtiles.mjs"));
let queries = null;
const loadQueries = lazy(() => import("./query.mjs").then((m) => (queries = m)));
// Starts loading labels early for a style with symbol layers; each tile still checks its own.
const prefetchSymbols = (symbols) => {
  if (canDrawGlyphs && symbols === true) loadSymbols().catch(() => {});
};

function hasSymbols(packed) {
  const view = new DataView(packed.buffer, packed.byteOffset, packed.byteLength);
  for (let k = view.getUint32(0, true) - 1; k >= 0; k--) {
    if (view.getUint32(4 + (k * LAYER_ENTRY_WORDS + 1) * 4, true) === KIND_SYMBOL) return true;
  }
  return false;
}

function withInput(bytes, run) {
  const addr = wasm.prepare_input(bytes.length);
  if (addr < 0) throw new Error("input too large");
  new Uint8Array(wasm.memory.buffer, addr, bytes.length).set(bytes);
  const n = run();
  // Output may have grown memory, so read through a fresh view.
  const out = wasm.output_addr();
  if (n < 0) throw new Error(decoder.decode(new Uint8Array(wasm.memory.buffer, out, -n)));
  return new Uint8Array(wasm.memory.buffer, out, n);
}

// Tags are @core.PROP_*. Without a prototype, a tile's `__proto__` key is an
// ordinary property.
function decodeProps(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const props = Object.create(null);
  let at = 4;
  for (let n = view.getUint32(0, true); n > 0; n--) {
    let key;
    [key, at] = readString(view, bytes, at);
    [props[key], at] = readValue(view, bytes, at);
  }
  return props;
}

function unpack(packed) {
  const view = new DataView(packed.buffer, packed.byteOffset, packed.byteLength);
  const count = view.getUint32(0, true);
  const layers = [];
  const transfer = [];
  const byOffset = new Map();
  for (let k = 0; k < count; k++) {
    const e = (i) => view.getUint32(4 + (k * LAYER_ENTRY_WORDS + i) * 4, true);
    const props = e(8) > 0 ? decodeProps(packed.subarray(e(7), e(7) + e(8))) : null;
    if (e(1) === KIND_SYMBOL) {
      if (!canDrawGlyphs) {
        if (!warned) postMessage({ type: "error", message: "labels need OffscreenCanvas" });
        warned = true;
        continue;
      }
      const s = symbols.buildSymbols(packed.subarray(e(2), e(2) + e(3)), glyphs, images);
      if (s.count === 0 && !(s.icon?.count > 0) && !s.missing?.length) continue;
      layers.push({ entry: k, layer: e(0), kind: e(1), shared: -1, props, ...s });
      transfer.push(s.vertices, s.indices, s.labels.buffer, s.codepoints.buffer);
      if (s.icon) transfer.push(s.icon.vertices, s.icon.indices);
      continue;
    }
    // The layer's own per-vertex paint, also over shared geometry.
    const paint = e(10) > 0 ? packed.slice(e(9), e(9) + e(10)).buffer : null;
    if (paint) transfer.push(paint);
    const shared = byOffset.get(e(2));
    if (shared !== undefined) {
      const { vertices, indices, outline, distances, progress, clips } = layers[shared];
      layers.push({ entry: k, layer: e(0), kind: e(1), vertices, indices, count: e(5), indexBytes: e(6), shared, props, paint, outline, outlineCount: e(12), distances, progress, clips });
      continue;
    }
    const vertices = packed.slice(e(2), e(2) + e(3)).buffer;
    const indices = packed.slice(e(4), e(4) + e(5) * e(6)).buffer;
    const outline = e(12) > 0 ? packed.slice(e(11), e(11) + e(12) * e(6)).buffer : null;
    if (outline) transfer.push(outline);
    const distances = e(14) > 0 ? packed.slice(e(13), e(13) + e(14) * 2).buffer : null;
    if (distances) transfer.push(distances);
    // A gradient line's progress (f32 share and row per vertex: 8 bytes, as its vertices), then its rows' clips and longest line (f64s).
    let progress = null, clips = null;
    if (e(15) > 0) {
      const end = e(15) + e(3);
      progress = packed.slice(e(15), end).buffer;
      clips = new Float64Array(packed.slice(end, end + e(16) * 16 + 8).buffer);
      transfer.push(progress, clips.buffer);
    }
    // `shared` names a position in `layers` (skipped symbol entries have none).
    byOffset.set(e(2), layers.length);
    layers.push({ entry: k, layer: e(0), kind: e(1), vertices, indices, count: e(5), indexBytes: e(6), shared: -1, props, paint, outline, outlineCount: e(12), distances, progress, clips });
    transfer.push(vertices, indices);
  }
  return { layers, transfer };
}

async function init({ wasm: url, style, symbols, font: family }) {
  if (typeof family === "string" && family) font = family;
  prefetchSymbols(symbols);
  const host = hostText();
  const { instance } = await WebAssembly.instantiateStreaming(fetch(url), { host, Math });
  wasm = instance.exports;
  withInput(style, () => wasm.init_style());
}

let demCanvas = null;
async function demPixels(bytes) {
  checkImageSize(bytes, MAX_DEM_SIZE, "DEM tile");
  const bitmap = await decodeImage(new Blob([bytes]));
  const size = bitmap.width;
  if (bitmap.height !== size || size > MAX_DEM_SIZE) {
    bitmap.close();
    throw new Error(`DEM tile is ${size} x ${bitmap.height}, not square up to ${MAX_DEM_SIZE}`);
  }
  if (demCanvas?.width !== size) demCanvas = new OffscreenCanvas(size, size);
  const ctx = demCanvas.getContext("2d", { willReadFrequently: true });
  ctx.drawImage(bitmap, 0, 0);
  bitmap.close();
  return { size, rgba: new Uint8Array(ctx.getImageData(0, 0, size, size).data.buffer) };
}

// What a `transformRequest` may set on a tile fetch: string headers and a
// credentials mode; anything else is left out.
function fetchInit(init, signal) {
  const out = { signal, credentials: "omit" };
  if (init && typeof init === "object") {
    if (["omit", "same-origin", "include"].includes(init.credentials)) out.credentials = init.credentials;
    if (init.headers && typeof init.headers === "object") {
      out.headers = Object.fromEntries(Object.entries(init.headers).filter(([, v]) => typeof v === "string"));
    }
  }
  return out;
}

async function loadTile({ id, url, init, bytes: given, source, z, dem, raster }) {
  const controller = new AbortController();
  pending.set(id, controller);
  try {
    let bytes;
    if (!Number.isInteger(source) || !Number.isInteger(z)) throw new Error("malformed tile message");
    const pmtiles = !(given instanceof ArrayBuffer) && typeof url === "string" && url.startsWith("pmtiles://") ? await loadPmtiles() : null;
    const pm = pmtiles?.splitTileUrl(url);
    if (controller.signal.aborted) return;
    if (given instanceof ArrayBuffer) {
      bytes = new Uint8Array(given);
    } else if (pm) {
      let archive = archives.get(pm.archive);
      if (!archive) {
        if (archives.size >= MAX_ARCHIVES) archives.delete(archives.keys().next().value);
        archives.set(pm.archive, (archive = new pmtiles.Archive(pm.archive, (u, o, l) => pmtiles.fetchRange(u, o, l))));
      }
      bytes = await archive.tile(pm.z, pm.x, pm.y);
      if (!bytes) {
        postMessage({ type: "tile", id, layers: [] });
        return;
      }
    } else {
      // Never data:, blob: or file: URLs (AGENTS.md §8.3), whatever made the template.
      if (typeof url !== "string" || !/^https?:\/\//i.test(url)) throw new Error("tile URL must be http(s)");
      const res = await fetch(url, fetchInit(init, controller.signal));
      if (res.status === 404 || res.status === 204) {
        postMessage({ type: "tile", id, layers: [] });
        return;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      bytes = await readCapped(res);
    }
    if (controller.signal.aborted) return;
    if (raster === true) {
      checkImageSize(bytes, MAX_RASTER_SIZE, "raster tile");
      // Premultiplied, as MapLibre uploads raster tiles (its shader divides it out).
      const image = await createImageBitmap(new Blob([bytes]), { premultiplyAlpha: "premultiply" });
      if (controller.signal.aborted) return image.close();
      if (image.width > MAX_RASTER_SIZE || image.height > MAX_RASTER_SIZE) {
        image.close();
        throw new Error(`raster tile is ${image.width} x ${image.height}, over ${MAX_RASTER_SIZE}`);
      }
      postMessage({ type: "tile", id, layers: [{ entry: 0, layer: -1, kind: KIND_RASTER, image }], glyphs: [] }, [image]);
      return;
    }
    if (dem === true) {
      const { size, rgba } = await demPixels(bytes);
      if (controller.signal.aborted) return;
      // Slopes, border elevations (f64) and elevations (f32): worker/processor.mbt `dem_tile`.
      const out = withInput(rgba, () => wasm.process_dem(source, z, size));
      const s = (size + 2) * (size + 2) * 2;
      const image = out.slice(0, s).buffer;
      const edges = new Float64Array(out.slice(s, s + 8 * size * 8).buffer);
      const elevations = new Float32Array(out.slice(s + 8 * size * 8).buffer);
      postMessage({ type: "tile", id, layers: [{ layer: -1, kind: KIND_HILLSHADE, image, edges, elevations, size }], glyphs: [] }, [image, edges.buffer, elevations.buffer]);
      return;
    }
    await imagesReady;
    if (controller.signal.aborted) return;
    let packed = withInput(bytes, () => wasm.process_tile(source, z));
    const featureRanges = () => readFeatureRanges(withInput(new Uint8Array(0), () => wasm.feature_ranges()));
    let ranges = null;
    if (!symbols && canDrawGlyphs && hasSymbols(packed)) {
      // Other tiles use the wasm while labels load: this tile's output is kept first.
      packed = packed.slice();
      ranges = featureRanges();
      await loadSymbols();
      if (controller.signal.aborted) return;
    }
    glyphs?.startTile();
    const { layers, transfer } = unpack(packed);
    ranges ??= featureRanges();
    if (controller.signal.aborted) return;
    // New glyphs go with the first tile posted after they were drawn; the main
    // thread takes them even from tiles it no longer wants.
    const fresh = glyphs?.take() ?? [];
    kept.set(id, { bytes, ranges });
    postMessage({ type: "tile", id, layers, glyphs: fresh }, [...transfer, ...fresh.map((g) => g.data.buffer)]);
  } catch (err) {
    if (!controller.signal.aborted) postMessage({ type: "tile-error", id, message: String(err?.message ?? err) });
  } finally {
    pending.delete(id);
  }
}

// A query of a kept tile (`features`: of its source layer, else of what is
// drawn), answered with GeoJSON features; none if the tile is gone or query.mjs failed to load.
function query({ id, kind, tile, source, z, x, y, request }) {
  const bytes = kept.get(tile)?.bytes;
  let hits = [];
  if (queries && bytes && ArrayBuffer.isView(request)) {
    const input = new Uint8Array(bytes.length + request.byteLength);
    input.set(bytes);
    input.set(new Uint8Array(request.buffer, request.byteOffset, request.byteLength), bytes.length);
    const run = kind === "features" ? wasm.source_features : wasm.query_tile;
    try {
      hits = queries.readQueryResult(withInput(input, () => run(source, z, bytes.length)), z, x, y);
    } catch (err) {
      postMessage({ type: "error", message: String(err?.message ?? err) });
    }
  }
  postMessage({ type: "query", id, hits });
}

const failure = (err) => String(err?.message ?? err);

// Messages are answered even when init failed, so the main thread's waits end:
// tiles with `tile-error`, queries and ranges with nothing found.
onmessage = (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready) {
    ready = init(msg);
    ready.then(
      () => postMessage({ type: "ready" }),
      (err) => postMessage({ type: "error", message: failure(err) }),
    );
  } else if (msg?.type === "style" && ready && msg.style instanceof Uint8Array) {
    // Tiles asked for after this message are made with the new style; a style
    // that fails is reported, and `ready` stays usable (once the wasm runs).
    const style = msg.style;
    prefetchSymbols(msg.symbols);
    const apply = () => {
      try {
        withInput(style, () => wasm.init_style());
      } catch (err) {
        postMessage({ type: "error", message: failure(err) });
      }
    };
    ready = ready.then(apply, (err) => {
      if (!wasm) throw err;
      apply();
    });
  } else if (msg?.type === "tile" && ready && Number.isInteger(msg.id)) {
    // Tiles requested before init finished wait for it.
    ready.then(() => loadTile(msg), (err) => postMessage({ type: "tile-error", id: msg.id, message: failure(err) }));
  } else if (msg?.type === "query" && ready && Number.isInteger(msg.id) && Number.isInteger(msg.tile)) {
    // What comes after the first query (a `drop` of its tile, a new style) waits for the module.
    if (!queries) ready = ready.then(() => loadQueries().catch((err) => postMessage({ type: "error", message: failure(err) })));
    ready.then(() => query(msg), () => postMessage({ type: "query", id: msg.id, hits: [] }));
  } else if (msg?.type === "ranges" && ready && Number.isInteger(msg.id) && Number.isInteger(msg.tile) && Array.isArray(msg.ids)) {
    // Where the features with these ids lie in the tile's entries.
    ready.then(() => {
      const ranges = kept.get(msg.tile)?.ranges;
      postMessage({ type: "ranges", id: msg.id, entries: ranges ? rangesOf(ranges, msg.ids.map(String)) : [] });
    }, () => postMessage({ type: "ranges", id: msg.id, entries: [] }));
  } else if (msg?.type === "drop" && ready && Number.isInteger(msg.id)) {
    // After the queries asked before it.
    ready.then(() => kept.delete(msg.id), () => {});
  } else if (msg?.type === "images" && Array.isArray(msg.images)) {
    images = new Map(msg.images.filter((i) => Array.isArray(i) && typeof i[0] === "string").map(([name, ...meta]) => [name, meta]));
    if (msg.loading === true && !imagesLoaded) {
      imagesReady = new Promise((resolve) => (imagesLoaded = resolve));
    } else if (msg.loading !== true && imagesLoaded) {
      imagesLoaded();
      imagesLoaded = null;
    }
  } else if (msg?.type === "cancel" && Number.isInteger(msg.id)) {
    pending.get(msg.id)?.abort();
  }
};
