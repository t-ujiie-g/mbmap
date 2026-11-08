// Glue around the wasm-gc build of `model_worker` (meshopt and Draco decoding): reads glTF models for mbmap/3d
// (`npm/src/model/gltf.ts`) and decodes their images; messages are in docs/FORMATS.md ("Model worker
// messages").

import { writeInput } from "../../wasmio/js/host.mjs";
import { readGltf } from "../../npm/src/model/gltf.ts";
import { readTileContent } from "../../npm/src/tiles/content.ts";

/** meshopt's modes and filters as the wasm numbers them. */
const MODES = { ATTRIBUTES: 0, TRIANGLES: 1, INDICES: 2 };
const FILTERS = { NONE: 0, OCTAHEDRAL: 1, QUATERNION: 2, EXPONENTIAL: 3, COLOR: 4 };

let wasmUrl = null;
let wasm = null;

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

async function fetchBytes(url) {
  if (!isHttp(url)) throw new Error(`cannot load ${url.protocol} URLs`);
  const res = await fetch(url, { credentials: "omit" });
  if (!res.ok) throw new Error(`${url.href}: HTTP ${res.status}`);
  return new Uint8Array(await res.arrayBuffer());
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

async function tile({ url }) {
  const base = new URL(url);
  const exports = await instance();
  const content = await readTileContent(await fetchBytes(base), (uri) => fetchBytes(new URL(uri, base)), meshopt(exports), draco(exports));
  const images = await Promise.all(content.model.images.map(bitmap));
  return { primitives: content.model.primitives, materials: content.model.materials, images, rtc: content.rtc, batchLength: content.batchLength };
}

const OPS = { load, tile };

/** Every ArrayBuffer and ImageBitmap of `value`, once each. */
function transferables(value) {
  const out = new Set(value.images);
  for (const p of value.primitives) {
    for (const a of Object.values(p.attributes)) out.add(a.data.buffer);
    if (p.indices) out.add(p.indices.buffer);
  }
  return [...out];
}

onmessage = async (e) => {
  const msg = e.data;
  if (msg?.type === "init" && wasmUrl === null && typeof msg.wasm === "string") {
    wasmUrl = msg.wasm;
  } else if (msg?.type === "call" && wasmUrl !== null && Number.isInteger(msg.id) && Object.hasOwn(OPS, msg.op) && typeof msg.url === "string") {
    try {
      const value = await OPS[msg.op](msg);
      postMessage({ type: "result", id: msg.id, value }, transferables(value));
    } catch (err) {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    }
  }
};
