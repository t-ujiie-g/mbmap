// Glue around the wasm-gc build of `model_worker` (meshopt decoding): reads glTF models for mbmap/3d
// (`npm/src/model/gltf.ts`) and decodes their images; messages are in docs/FORMATS.md ("Model worker
// messages").

import { writeInput } from "../../wasmio/js/host.mjs";
import { readGltf } from "../../npm/src/model/gltf.ts";

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
  const model = await readGltf(bytes, (uri) => fetchBytes(new URL(uri, base)), meshopt(await instance()));
  const images = await Promise.all(model.images.map(bitmap));
  return { primitives: model.primitives, materials: model.materials, images };
}

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
  } else if (msg?.type === "call" && wasmUrl !== null && Number.isInteger(msg.id) && msg.op === "load" && typeof msg.url === "string") {
    try {
      const value = await load(msg);
      postMessage({ type: "result", id: msg.id, value }, transferables(value));
    } catch (err) {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    }
  }
};
