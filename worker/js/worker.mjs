// Glue around the wasm-gc build of `worker`. Messages and the packed tile are in
// docs/FORMATS.md ("Display worker messages", "Packed tile").

import { hostNumber } from "../../wasmio/js/host.mjs";
import { readCapped } from "./body.mjs";
import { Archive, fetchRange, splitTileUrl } from "./pmtiles.mjs";
import { rangesOf, readFeatureRanges, readQueryResult } from "./query.mjs";
import { buildSymbols, Glyphs } from "./symbols.mjs";
import { readString, readValue } from "./values.mjs";

const LAYER_ENTRY_WORDS = 15; // worker/packed.mbt
const KIND_SYMBOL = 4; // worker/packed.mbt
const KIND_HILLSHADE = 5; // map/tiles.mbt
const KIND_RASTER = 7; // map/tiles.mbt
// Largest DEM tile side (worker/processor.mbt `dem_tile`) and raster tile side.
const MAX_DEM_SIZE = 1024;
const MAX_RASTER_SIZE = 4096;
// PMTiles archives kept open at once.
const MAX_ARCHIVES = 16;
const encoder = new TextEncoder();
const decoder = new TextDecoder();
let wasm = null;
let ready = null;
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
      const s = buildSymbols(packed.subarray(e(2), e(2) + e(3)), glyphs);
      if (s.count === 0) continue;
      layers.push({ entry: k, layer: e(0), kind: e(1), shared: -1, props, ...s });
      transfer.push(s.vertices, s.indices, s.labels.buffer, s.codepoints.buffer);
      continue;
    }
    // The layer's own per-vertex paint, also over shared geometry.
    const paint = e(10) > 0 ? packed.slice(e(9), e(9) + e(10)).buffer : null;
    if (paint) transfer.push(paint);
    const shared = byOffset.get(e(2));
    if (shared !== undefined) {
      const { vertices, indices, outline, distances } = layers[shared];
      layers.push({ entry: k, layer: e(0), kind: e(1), vertices, indices, count: e(5), indexBytes: e(6), shared, props, paint, outline, outlineCount: e(12), distances });
      continue;
    }
    const vertices = packed.slice(e(2), e(2) + e(3)).buffer;
    const indices = packed.slice(e(4), e(4) + e(5) * e(6)).buffer;
    const outline = e(12) > 0 ? packed.slice(e(11), e(11) + e(12) * e(6)).buffer : null;
    if (outline) transfer.push(outline);
    const distances = e(14) > 0 ? packed.slice(e(13), e(13) + e(14) * 2).buffer : null;
    if (distances) transfer.push(distances);
    // `shared` names a position in `layers` (skipped symbol entries have none).
    byOffset.set(e(2), layers.length);
    layers.push({ entry: k, layer: e(0), kind: e(1), vertices, indices, count: e(5), indexBytes: e(6), shared: -1, props, paint, outline, outlineCount: e(12), distances });
    transfer.push(vertices, indices);
  }
  return { layers, transfer };
}

async function init({ wasm: url, style, font }) {
  glyphs = new Glyphs(typeof font === "string" && font ? font : "sans-serif");
  const host = { number: hostNumber(() => wasm.memory) };
  const { instance } = await WebAssembly.instantiateStreaming(fetch(url), { host, Math });
  wasm = instance.exports;
  withInput(encoder.encode(style), () => wasm.init_style());
}

// A DEM tile's pixels exactly as stored: no color management, no premultiplying.
let demCanvas = null;
async function demPixels(bytes) {
  const bitmap = await createImageBitmap(new Blob([bytes]), { premultiplyAlpha: "none", colorSpaceConversion: "none" });
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
    const pm = typeof url === "string" ? splitTileUrl(url) : null;
    if (given instanceof ArrayBuffer) {
      bytes = new Uint8Array(given);
    } else if (pm) {
      let archive = archives.get(pm.archive);
      if (!archive) {
        if (archives.size >= MAX_ARCHIVES) archives.delete(archives.keys().next().value);
        archives.set(pm.archive, (archive = new Archive(pm.archive, (u, o, l) => fetchRange(u, o, l))));
      }
      bytes = await archive.tile(pm.z, pm.x, pm.y);
      if (!bytes) {
        postMessage({ type: "tile", id, layers: [] });
        return;
      }
    } else {
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
      const s = size * size * 2;
      const image = out.slice(0, s).buffer;
      const edges = new Float64Array(out.slice(s, s + 8 * size * 8).buffer);
      const elevations = new Float32Array(out.slice(s + 8 * size * 8).buffer);
      postMessage({ type: "tile", id, layers: [{ layer: -1, kind: KIND_HILLSHADE, image, edges, elevations, size }], glyphs: [] }, [image, edges.buffer, elevations.buffer]);
      return;
    }
    glyphs.startTile();
    const { layers, transfer } = unpack(withInput(bytes, () => wasm.process_tile(source, z)));
    if (controller.signal.aborted) return;
    // New glyphs go with the first tile posted after they were drawn; the main
    // thread takes them even from tiles it no longer wants.
    const fresh = glyphs.take();
    kept.set(id, { bytes, ranges: readFeatureRanges(withInput(new Uint8Array(0), () => wasm.feature_ranges())) });
    postMessage({ type: "tile", id, layers, glyphs: fresh }, [...transfer, ...fresh.map((g) => g.data.buffer)]);
  } catch (err) {
    if (!controller.signal.aborted) postMessage({ type: "tile-error", id, message: String(err?.message ?? err) });
  } finally {
    pending.delete(id);
  }
}

// A query of a kept tile (`features`: of its source layer, else of what is
// drawn), answered with GeoJSON features; none if the tile is gone.
function query({ id, kind, tile, source, z, x, y, request }) {
  const bytes = kept.get(tile)?.bytes;
  let hits = [];
  if (bytes && ArrayBuffer.isView(request)) {
    const input = new Uint8Array(bytes.length + request.byteLength);
    input.set(bytes);
    input.set(new Uint8Array(request.buffer, request.byteOffset, request.byteLength), bytes.length);
    const run = kind === "features" ? wasm.source_features : wasm.query_tile;
    try {
      hits = readQueryResult(withInput(input, () => run(source, z, bytes.length)), z, x, y);
    } catch (err) {
      postMessage({ type: "error", message: String(err?.message ?? err) });
    }
  }
  postMessage({ type: "query", id, hits });
}

onmessage = (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready) {
    ready = init(msg);
    ready.then(
      () => postMessage({ type: "ready" }),
      (err) => postMessage({ type: "error", message: String(err?.message ?? err) }),
    );
  } else if (msg?.type === "style" && ready && typeof msg.style === "string") {
    // Tiles asked for after this message are made with the new style.
    const style = encoder.encode(msg.style);
    ready = ready.then(() => withInput(style, () => wasm.init_style()));
  } else if (msg?.type === "tile" && ready) {
    // Tiles requested before init finished wait for it.
    ready.then(() => loadTile(msg), () => {});
  } else if (msg?.type === "query" && ready && Number.isInteger(msg.id) && Number.isInteger(msg.tile)) {
    ready.then(() => query(msg), () => {});
  } else if (msg?.type === "ranges" && ready && Number.isInteger(msg.id) && Array.isArray(msg.ids)) {
    // Where the features with these ids lie in the tile's entries.
    ready.then(() => {
      const ranges = kept.get(msg.tile)?.ranges;
      postMessage({ type: "ranges", id: msg.id, entries: ranges ? rangesOf(ranges, msg.ids.map(String)) : [] });
    }, () => {});
  } else if (msg?.type === "drop" && ready) {
    // After the queries asked before it.
    ready.then(() => kept.delete(msg.id), () => {});
  } else if (msg?.type === "cancel") {
    pending.get(msg.id)?.abort();
  }
};
