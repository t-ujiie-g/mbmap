// Glue around the wasm-gc build of `geojson_worker`; messages are in
// docs/FORMATS.md ("GeoJSON worker messages").

import { hostNumber } from "../../wasmio/js/host.mjs";

const decoder = new TextDecoder();
let wasm = null;
let ready = null;
const loads = new Map();

function input(bytes) {
  const addr = wasm.prepare_input(bytes.length);
  if (addr < 0) throw new Error(`GeoJSON too large (${bytes.length} bytes)`);
  new Uint8Array(wasm.memory.buffer, addr, bytes.length).set(bytes);
}

async function load({ source, url, bytes, maxzoom, buffer, tolerance }, previous) {
  await ready;
  // A source loaded again keeps the order of its loads.
  await previous?.catch(() => {});
  let data = bytes instanceof ArrayBuffer ? new Uint8Array(bytes) : null;
  if (!data) {
    if (typeof url !== "string" || !/^https?:/.test(url)) throw new Error("data must be an http(s) URL");
    const res = await fetch(url, { credentials: "omit" });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    data = new Uint8Array(await res.arrayBuffer());
  }
  input(data);
  const n = wasm.load(source, maxzoom, buffer, tolerance);
  if (n < 0) throw new Error(decoder.decode(new Uint8Array(wasm.memory.buffer, wasm.output_addr(), -n)));
  return n;
}

function tile({ id, source, z, x, y }) {
  const n = wasm.tile(source, z, x, y);
  if (n < 0) throw new Error("source not loaded");
  if (n === 0) return postMessage({ type: "tile", id, bytes: null });
  const bytes = new Uint8Array(wasm.memory.buffer, wasm.output_addr(), n).slice().buffer;
  postMessage({ type: "tile", id, bytes }, [bytes]);
}

onmessage = (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready) {
    const host = { number: hostNumber(() => wasm.memory) };
    ready = WebAssembly.instantiateStreaming(fetch(msg.wasm), { Math: { sin: Math.sin, log: Math.log }, host })
      .then(({ instance }) => { wasm = instance.exports; });
  } else if (msg?.type === "load" && ready && Number.isInteger(msg.source)) {
    const done = load(msg, loads.get(msg.source));
    loads.set(msg.source, done);
    done.then(
      (features) => postMessage({ type: "loaded", source: msg.source, features }),
      (err) => postMessage({ type: "error", source: msg.source, message: String(err?.message ?? err) }),
    );
  } else if (msg?.type === "unload" && Number.isInteger(msg.source)) {
    const done = loads.get(msg.source);
    loads.delete(msg.source);
    done?.catch(() => {}).then(() => wasm.unload(msg.source));
  } else if (msg?.type === "tile" && Number.isInteger(msg.id)) {
    const none = () => postMessage({ type: "tile", id: msg.id, bytes: null });
    const done = loads.get(msg.source);
    if (done) done.then(() => tile(msg)).catch(none);
    else none();
  }
};
