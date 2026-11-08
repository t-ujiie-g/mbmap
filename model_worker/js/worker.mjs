// Glue around the wasm-gc build of `model_worker` (meshopt and Draco decoding): reads glTF models for mbmap/3d
// (`npm/src/model/gltf.ts`) and decodes their images, and LAS point clouds (`npm/src/model/las.ts`) taken
// to WGS 84 through proj.wasm; messages are in docs/FORMATS.md ("Model worker messages").

import { transformPairs } from "../../data_worker/js/crs.mjs";
import { writeInput } from "../../wasmio/js/host.mjs";
import { readCapped } from "../../worker/js/body.mjs";
import { readGltf } from "../../npm/src/model/gltf.ts";
import { horizontalWkt, MAX_LAS_BYTES, MAX_LAS_POINTS, readLas } from "../../npm/src/model/las.ts";
import { readTileContent } from "../../npm/src/tiles/content.ts";
import { eastNorthUp, toCartesian } from "../../npm/src/tiles/geo.ts";

/** meshopt's modes and filters as the wasm numbers them. */
const MODES = { ATTRIBUTES: 0, TRIANGLES: 1, INDICES: 2 };
const FILTERS = { NONE: 0, OCTAHEDRAL: 1, QUATERNION: 2, EXPONENTIAL: 3, COLOR: 4 };

let wasmUrl = null;
let wasm = null;
// proj.wasm (with the host's Math, as proj4js computes) and the .prj WKT parser (prjwkt.js), each on first use.
const urls = {};
const loaded = {};
function lazy(name, start) {
  if (typeof urls[name] !== "string") return Promise.reject(new Error(`no URL for the ${name} module`));
  return (loaded[name] ??= start(urls[name]));
}
const proj = () => lazy("proj", (url) => WebAssembly.instantiateStreaming(fetch(url), { Math }).then(({ instance }) => instance.exports));
const prj = () => lazy("prj", (url) => import(url));

async function instance() {
  if (!wasm) {
    const { instance } = await WebAssembly.instantiateStreaming(fetch(wasmUrl), {});
    wasm = instance.exports;
  }
  return wasm;
}

function meshopt(exports) {
  return (target, count, size, source, mode, filter) => {
    const m = MODES[mode];
    const f = FILTERS[filter];
    if (m === undefined || f === undefined) throw new Error(`unknown meshopt mode or filter ${mode} ${filter}`);
    writeInput(exports, [source], "meshopt data");
    const n = exports.meshopt_decode(count, size, m, f);
    if (n !== target.length) throw new Error("meshopt data could not be decoded");
    target.set(new Uint8Array(exports.memory.buffer, exports.output_addr(), n));
  };
}

/** The typed array of each Draco data type that glTF can hold (docs/FORMATS.md "Draco output"). */
const DRACO_TYPES = { 1: [Int8Array, 5120], 2: [Uint8Array, 5121], 3: [Int16Array, 5122], 4: [Uint16Array, 5123], 6: [Uint32Array, 5125], 9: [Float32Array, 5126] };

/** Decodes a KHR_draco_mesh_compression buffer view through the wasm's `draco_decode`. */
function draco(exports) {
  return (bytes) => {
    writeInput(exports, [bytes], "Draco data");
    const n = exports.draco_decode();
    if (n === -2) throw new Error("out of memory");
    if (n < 0) throw new Error("Draco data could not be decoded");
    const out = new Uint8Array(exports.memory.buffer.slice(exports.output_addr(), exports.output_addr() + n));
    const v = new DataView(out.buffer);
    const [faces, , count] = [v.getUint32(0, true), v.getUint32(4, true), v.getUint32(8, true)];
    const heads = [];
    for (let i = 0; i < count; i++) {
      const at = 12 + i * 12;
      heads.push({ id: v.getUint32(at, true), type: v.getUint8(at + 5), size: v.getUint8(at + 6), normalized: v.getUint8(at + 7) === 1, length: v.getUint32(at + 8, true) });
    }
    let at = 12 + count * 12;
    const indices = new Uint32Array(out.buffer.slice(at, at + faces * 12));
    at += faces * 12;
    const attributes = new Map();
    for (const h of heads) {
      const kind = DRACO_TYPES[h.type];
      if (!kind) throw new Error(`Draco data type ${h.type} has no glTF counterpart`);
      const [Typed, type] = kind;
      attributes.set(h.id, { data: new Typed(out.buffer.slice(at, at + h.length)), size: h.size, type, normalized: h.normalized });
      at += (h.length + 3) & ~3;
    }
    return { indices, attributes };
  };
}

const isHttp = (url) => url.protocol === "http:" || url.protocol === "https:" || url.protocol === "blob:" || url.protocol === "data:";

async function fetchBytes(url, max) {
  if (!isHttp(url)) throw new Error(`cannot load ${url.protocol} URLs`);
  const res = await fetch(url, { credentials: "omit" });
  if (!res.ok) throw new Error(`${url.href}: HTTP ${res.status}`);
  return max === undefined ? new Uint8Array(await res.arrayBuffer()) : readCapped(res, max);
}

/** Decodes an image's bytes into an ImageBitmap as uploaded (no premultiplying or color conversion). */
const bitmap = (image) =>
  createImageBitmap(new Blob([image.bytes], { type: image.mimeType }), { premultiplyAlpha: "none", colorSpaceConversion: "none" });

async function load({ url }) {
  const base = new URL(url);
  const bytes = await fetchBytes(base);
  const exports = await instance();
  const model = await readGltf(bytes, (uri) => fetchBytes(new URL(uri, base)), meshopt(exports), draco(exports));
  const images = await Promise.all(model.images.map(bitmap));
  return { primitives: model.primitives, materials: model.materials, images };
}

/** A tile's content as parts to draw: a cmpt's inner tiles, else the content itself. */
async function tile({ url }) {
  const base = new URL(url);
  const exports = await instance();
  const content = await readTileContent(await fetchBytes(base), (uri) => fetchBytes(new URL(uri, base)), meshopt(exports), draco(exports));
  const parts = content.kind === "cmpt" ? content.parts : [content];
  return {
    parts: await Promise.all(
      parts.map(async (c) => ({
        kind: c.kind,
        primitives: c.model.primitives,
        materials: c.model.materials,
        images: await Promise.all(c.model.images.map(bitmap)),
        rtc: c.rtc,
        batchLength: c.batchLength,
        batchTable: c.batchTable,
        batchBinary: c.batchBinary.slice(),
        instances: c.instances,
        metadata: c.model.metadata,
      })),
    ),
  };
}

// `@proj.DEFINITION_SLOTS` (proj/encoding.mbt), as data_worker/js/read.mjs's `isCrs`.
const DEFINITION_SLOTS = 34;
const isCrs = (c) => (Number.isInteger(c) && c > 0) || (c instanceof Float64Array && c.length === DEFINITION_SLOTS);
const isLonLat = (crs) => crs === 4326 || crs === 4979 || crs?.code === 4326 || crs?.code === 4979;
// Points per proj.wasm call: the pairs and the answer both sit in its memory.
const PAIRS_PER_CALL = 1 << 22;

/** The CRS of a LAS file's coordinates as proj.wasm takes them: `given`, else the file's EPSG code, else its WKT parsed. */
async function lasCrs(given, stated) {
  if (given !== undefined) return given;
  if (stated?.epsg !== undefined) return stated.epsg;
  if (stated?.wkt !== undefined) return (await prj()).parsePrj(horizontalWkt(stated.wkt));
  throw new Error("LAS: the file states no CRS; give crs");
}

/** Longitude, latitude and height per point of `positions` (x, y, z in `crs`), heights as they are. */
async function toLonLatHeight(positions, crs) {
  if (isLonLat(crs)) return positions;
  const exports = await proj();
  const n = positions.length / 3;
  const out = new Float64Array(positions.length);
  for (let start = 0; start < n; start += PAIRS_PER_CALL) {
    const m = Math.min(PAIRS_PER_CALL, n - start);
    const xy = new Float64Array(m * 2);
    for (let i = 0; i < m; i++) {
      xy[i * 2] = positions[(start + i) * 3];
      xy[i * 2 + 1] = positions[(start + i) * 3 + 1];
    }
    const lonLat = transformPairs(exports, crs, 4326, xy);
    for (let i = 0; i < m; i++) {
      const [lon, lat] = [lonLat[i * 2], lonLat[i * 2 + 1]];
      if (Number.isNaN(lon) || Number.isNaN(lat)) throw new Error("LAS: coordinates out of reach of the CRS");
      out.set([lon, lat, positions[(start + i) * 3 + 2]], (start + i) * 3);
    }
  }
  return out;
}

/**
 * A LAS point cloud at `url` (thinned to `maxPoints`) in east, north, up meters around the center of its
 * bounds, through the WGS 84 east-north-up frame there; `crs` (an EPSG code or a definition) overrides the file's.
 */
async function las({ url, maxPoints, crs }) {
  if (!(Number.isInteger(maxPoints) && maxPoints > 0 && maxPoints <= MAX_LAS_POINTS) || !(crs === undefined || isCrs(crs))) throw new Error("invalid arguments");
  const cloud = readLas(await fetchBytes(new URL(url), MAX_LAS_BYTES), maxPoints);
  const geo = await toLonLatHeight(cloud.positions, await lasCrs(crs, cloud.crs));
  const lo = [Infinity, Infinity, Infinity];
  const hi = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < geo.length; i++) {
    lo[i % 3] = Math.min(lo[i % 3], geo[i]);
    hi[i % 3] = Math.max(hi[i % 3], geo[i]);
  }
  const center = cloud.kept > 0 ? [0, 1, 2].map((k) => (lo[k] + hi[k]) / 2) : [0, 0, 0];
  const origin = toCartesian(center[0], center[1], center[2]);
  const m = eastNorthUp(origin);
  const positions = new Float32Array(geo.length);
  for (let i = 0; i < geo.length; i += 3) {
    const p = toCartesian(geo[i], geo[i + 1], geo[i + 2]);
    const [dx, dy, dz] = [p[0] - origin[0], p[1] - origin[1], p[2] - origin[2]];
    positions[i] = m[0] * dx + m[1] * dy + m[2] * dz;
    positions[i + 1] = m[4] * dx + m[5] * dy + m[6] * dz;
    positions[i + 2] = m[8] * dx + m[9] * dy + m[10] * dz;
  }
  const bounds = cloud.kept > 0 ? [lo[0], lo[1], lo[2], hi[0], hi[1], hi[2]] : [0, 0, 0, 0, 0, 0];
  const { colors, intensity, classification, count, kept } = cloud;
  return { center, positions, colors, intensity, classification, count, kept, bounds };
}

const OPS = { load, tile, las };

/** Every ArrayBuffer and ImageBitmap of a model, a tile's parts or a point cloud, once each. */
function transferables(value) {
  if (value.positions) return [value.positions, value.colors, value.intensity, value.classification].filter(Boolean).map((a) => a.buffer);
  const out = new Set();
  for (const part of value.parts ?? [value]) {
    for (const image of part.images) out.add(image);
    for (const p of part.primitives) {
      for (const a of Object.values(p.attributes)) out.add(a.data.buffer);
      if (p.indices) out.add(p.indices.buffer);
    }
    if (part.instances) for (const a of [part.instances.matrices, part.instances.batchIds]) out.add(a.buffer);
  }
  return [...out];
}

onmessage = async (e) => {
  const msg = e.data;
  if (msg?.type === "init" && wasmUrl === null && typeof msg.wasm === "string") {
    wasmUrl = msg.wasm;
    urls.proj = msg.proj;
    urls.prj = msg.prj;
  } else if (msg?.type === "call" && wasmUrl !== null && Number.isInteger(msg.id) && Object.hasOwn(OPS, msg.op) && typeof msg.url === "string") {
    try {
      const value = await OPS[msg.op](msg);
      postMessage({ type: "result", id: msg.id, value }, transferables(value));
    } catch (err) {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    }
  }
};
