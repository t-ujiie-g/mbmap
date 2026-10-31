// Glue around the wasm-gc build of `worker`. Messages and the packed tile are in
// docs/FORMATS.md ("Display worker messages", "Packed tile").

import { buildSymbols, Glyphs } from "./symbols.mjs";

const LAYER_ENTRY_WORDS = 9; // worker/packed.mbt
const KIND_SYMBOL = 4; // worker/packed.mbt
const encoder = new TextEncoder();
const decoder = new TextDecoder();
let wasm = null;
let ready = null;
let glyphs = null;
// Without OffscreenCanvas (Safari before 16.4) labels are left out, once said.
const canDrawGlyphs = typeof OffscreenCanvas !== "undefined";
let warned = false;
const pending = new Map();

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
  let at = 0;
  const u32 = () => { const v = view.getUint32(at, true); at += 4; return v; };
  const str = () => { const n = u32(); const s = decoder.decode(bytes.subarray(at, at + n)); at += n; return s; };
  const props = Object.create(null);
  for (let n = u32(); n > 0; n--) {
    const key = str();
    const type = bytes[at++];
    if (type === 3) { props[key] = view.getFloat64(at, true); at += 8; }
    else if (type === 4) props[key] = str();
    else props[key] = type === 0 ? null : type === 2;
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
      layers.push({ layer: e(0), kind: e(1), shared: -1, props, ...s });
      transfer.push(s.vertices, s.indices, s.labels.buffer, s.codepoints.buffer);
      continue;
    }
    const shared = byOffset.get(e(2));
    if (shared !== undefined) {
      const { vertices, indices } = layers[shared];
      layers.push({ layer: e(0), kind: e(1), vertices, indices, count: e(5), indexBytes: e(6), shared, props });
      continue;
    }
    const vertices = packed.slice(e(2), e(2) + e(3)).buffer;
    const indices = packed.slice(e(4), e(4) + e(5) * e(6)).buffer;
    byOffset.set(e(2), k);
    layers.push({ layer: e(0), kind: e(1), vertices, indices, count: e(5), indexBytes: e(6), shared: -1, props });
    transfer.push(vertices, indices);
  }
  return { layers, transfer };
}

async function init({ wasm: url, style, font }) {
  glyphs = new Glyphs(typeof font === "string" && font ? font : "sans-serif");
  const { instance } = await WebAssembly.instantiateStreaming(fetch(url), {});
  wasm = instance.exports;
  withInput(encoder.encode(style), () => wasm.init_style());
}

async function loadTile({ id, url, bytes: given, source, z }) {
  const controller = new AbortController();
  pending.set(id, controller);
  try {
    let bytes;
    if (given instanceof ArrayBuffer) {
      bytes = new Uint8Array(given);
    } else {
      const res = await fetch(url, { signal: controller.signal, credentials: "omit" });
      if (res.status === 404 || res.status === 204) {
        postMessage({ type: "tile", id, layers: [] });
        return;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      bytes = new Uint8Array(await res.arrayBuffer());
    }
    if (controller.signal.aborted) return;
    glyphs.startTile();
    const { layers, transfer } = unpack(withInput(bytes, () => wasm.process_tile(source, z)));
    if (controller.signal.aborted) return;
    // New glyphs go with the first tile posted after they were drawn; the main
    // thread takes them even from tiles it no longer wants.
    const fresh = glyphs.take();
    postMessage({ type: "tile", id, layers, glyphs: fresh }, [...transfer, ...fresh.map((g) => g.data.buffer)]);
  } catch (err) {
    if (!controller.signal.aborted) postMessage({ type: "tile-error", id, message: String(err?.message ?? err) });
  } finally {
    pending.delete(id);
  }
}

onmessage = (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready) {
    ready = init(msg);
    ready.then(
      () => postMessage({ type: "ready" }),
      (err) => postMessage({ type: "error", message: String(err?.message ?? err) }),
    );
  } else if (msg?.type === "tile" && ready) {
    // Tiles requested before init finished wait for it.
    ready.then(() => loadTile(msg), () => {});
  } else if (msg?.type === "cancel") {
    pending.get(msg.id)?.abort();
  }
};
