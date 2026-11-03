// Glue around the wasm-gc build of `geojson_worker`; messages are in
// docs/FORMATS.md ("GeoJSON worker messages").

import { hostNumber, MAX_INPUT_BYTES } from "../../wasmio/js/host.mjs";
import { readCapped } from "../../worker/js/body.mjs";
import { readClusterFeatures } from "./features.mjs";

const decoder = new TextDecoder();
let wasm = null;
let ready = null;
const loads = new Map();

function input(bytes) {
  const addr = wasm.prepare_input(bytes.length);
  if (addr < 0) throw new Error(`GeoJSON too large (${bytes.length} bytes)`);
  new Uint8Array(wasm.memory.buffer, addr, bytes.length).set(bytes);
}

const isInt32 = (v) => Number.isInteger(v) && v >= -(2 ** 31) && v < 2 ** 31;

async function load({ source, url, bytes, maxzoom, buffer, tolerance, lineMetrics, cluster }, previous) {
  await ready;
  // A source loaded again keeps the order of its loads.
  await previous?.catch(() => {});
  if (cluster && !(isInt32(cluster.maxZoom) && typeof cluster.radius === "number" && cluster.radius >= 0 && cluster.radius < Infinity && isInt32(cluster.minPoints))) {
    throw new Error("malformed cluster options");
  }
  let data = bytes instanceof ArrayBuffer ? new Uint8Array(bytes) : null;
  if (!data) {
    if (typeof url !== "string" || !/^https?:/.test(url)) throw new Error("data must be an http(s) URL");
    const res = await fetch(url, { credentials: "omit" });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    data = await readCapped(res, MAX_INPUT_BYTES);
  }
  input(data);
  const c = cluster ?? { maxZoom: 0, radius: 0, minPoints: 0 };
  const n = wasm.load(source, maxzoom, buffer, tolerance, lineMetrics === true ? 1 : 0, cluster ? 1 : 0, c.maxZoom, c.radius, c.minPoints);
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

// The answer to a cluster query: null for a source that does not cluster.
function cluster({ source, op, cluster: id, limit, offset }) {
  const clustered = wasm.clustered(source);
  if (clustered < 0) throw new Error("source not loaded");
  if (clustered === 0) return null;
  if (op === "expansion") return wasm.cluster_expansion_zoom(source, id);
  const n = op === "children" ? wasm.cluster_children(source, id) : wasm.cluster_leaves(source, id, limit, offset);
  if (n === -1) throw new Error(`No cluster with the specified id: ${id}`);
  if (n < 0) throw new Error("out of memory");
  return readClusterFeatures(new Uint8Array(wasm.memory.buffer, wasm.output_addr(), n));
}

const validCluster = (msg) =>
  Number.isInteger(msg.id) && ["expansion", "children", "leaves"].includes(msg.op) &&
  isInt32(msg.cluster) && (msg.op !== "leaves" || (isInt32(msg.limit) && isInt32(msg.offset)));

onmessage = (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready) {
    const host = { number: hostNumber(() => wasm.memory) };
    ready = WebAssembly.instantiateStreaming(fetch(msg.wasm), { Math, host })
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
  } else if (msg?.type === "cluster" && validCluster(msg)) {
    const done = loads.get(msg.source) ?? Promise.reject(new Error("source not loaded"));
    done.then(() => cluster(msg)).then(
      (result) => postMessage({ type: "cluster", id: msg.id, result }),
      (err) => postMessage({ type: "cluster", id: msg.id, error: String(err?.message ?? err) }),
    );
  } else if (msg?.type === "tile" && Number.isInteger(msg.id)) {
    const none = () => postMessage({ type: "tile", id: msg.id, bytes: null });
    const done = loads.get(msg.source);
    if (done) done.then(() => tile(msg)).catch(none);
    else none();
  }
};
