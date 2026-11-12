// Glue around the wasm-gc build of `services_worker`; messages are in
// docs/FORMATS.md ("Services worker messages").

import { readEsri, servicesImports } from "./read.mjs";

let wasm = null;
let ready = null;

onmessage = async (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready && typeof msg.wasm === "string") {
    ready = WebAssembly.instantiateStreaming(fetch(msg.wasm), servicesImports(() => wasm)).then(({ instance }) => {
      wasm = instance.exports;
    });
  } else if (msg?.type === "call" && ready && Number.isInteger(msg.id) && msg.op === "esri") {
    try {
      await ready;
      if (!(msg.bytes instanceof ArrayBuffer)) throw new Error("invalid arguments");
      postMessage({ type: "result", id: msg.id, value: readEsri(wasm, new Uint8Array(msg.bytes), msg.format) });
    } catch (err) {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    }
  } else if (msg?.type === "call" && Number.isInteger(msg.id)) {
    postMessage({ type: "result", id: msg.id, error: "unknown call" });
  }
};
