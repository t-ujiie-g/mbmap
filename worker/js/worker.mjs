// Worker glue around the wasm-gc build of the MoonBit `worker` package.
//
// Messages in:  {type: "init", wasm, style}            wasm URL, style JSON text
//               {type: "tile", id, url, source, z}      source = index into style.sources
//               {type: "cancel", id}
// Messages out: {type: "ready"} | {type: "error", message}
//               {type: "tile", id, layers: [{layer, kind, vertices, indices, count, indexBytes, shared, props}]}
//               where `shared` is the index of an earlier layer whose buffers it reuses, or -1,
//               and `props` the properties a data-driven layer's group shares, or null
//               {type: "tile-error", id, message}
// Vertex and index buffers are transferred, never copied (VISION §4-3).

const LAYER_ENTRY_WORDS = 9;
const encoder = new TextEncoder();
const decoder = new TextDecoder();
let wasm = null;
let ready = null;
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

function unpack(packed) {
  const view = new DataView(packed.buffer, packed.byteOffset, packed.byteLength);
  const count = view.getUint32(0, true);
  const layers = [];
  const transfer = [];
  const byOffset = new Map();
  for (let k = 0; k < count; k++) {
    const e = (i) => view.getUint32(4 + (k * LAYER_ENTRY_WORDS + i) * 4, true);
    const props = e(8) > 0 ? JSON.parse(decoder.decode(packed.subarray(e(7), e(7) + e(8)))) : null;
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

async function init({ wasm: url, style }) {
  const { instance } = await WebAssembly.instantiateStreaming(fetch(url), {});
  wasm = instance.exports;
  withInput(encoder.encode(style), () => wasm.init_style());
}

async function loadTile({ id, url, source, z }) {
  const controller = new AbortController();
  pending.set(id, controller);
  try {
    const res = await fetch(url, { signal: controller.signal, credentials: "omit" });
    if (res.status === 404 || res.status === 204) {
      postMessage({ type: "tile", id, layers: [] });
      return;
    }
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const bytes = new Uint8Array(await res.arrayBuffer());
    if (controller.signal.aborted) return;
    const { layers, transfer } = unpack(withInput(bytes, () => wasm.process_tile(source, z)));
    postMessage({ type: "tile", id, layers }, transfer);
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
