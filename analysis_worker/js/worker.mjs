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

const OPS = {
  load,
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
