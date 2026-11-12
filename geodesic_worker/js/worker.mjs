// Glue around the wasm-gc build of `geodesic_worker`; messages are in
// docs/FORMATS.md ("Geodesic worker messages").

import { writeInput } from "../../wasmio/js/host.mjs";

const decoder = new TextDecoder();
let wasm = null;
let ready = null;

// The f64s an export wrote, or the error it reported (-2: out of memory, else minus a message length).
function f64s(n) {
  if (n === -2) throw new Error("out of memory");
  const at = wasm.output_addr();
  if (n < 0) throw new Error(decoder.decode(new Uint8Array(wasm.memory.buffer, at, -n)));
  return new Float64Array(wasm.memory.buffer.slice(at, at + n * 8));
}

const input = (coords) => writeInput(wasm, [new Uint8Array(coords)]);

function check(ok) {
  if (!ok) throw new Error("invalid arguments");
}
const isCoords = (c) => c instanceof ArrayBuffer && c.byteLength % 16 === 0 && new Float64Array(c).every(Number.isFinite);
const isPoint = (p) => Array.isArray(p) && p.length === 2 && p.every(Number.isFinite);

const OPS = {
  inverse({ from, to }) {
    check(isPoint(from) && isPoint(to));
    return f64s(wasm.inverse(from[1], from[0], to[1], to[0]));
  },
  direct({ from, azimuth, distance }) {
    check(isPoint(from) && Number.isFinite(azimuth) && Number.isFinite(distance));
    return f64s(wasm.direct(from[1], from[0], azimuth, distance));
  },
  circle({ center, radius, steps }) {
    check(isPoint(center) && Number.isFinite(radius) && Number.isInteger(steps));
    return f64s(wasm.circle(center[0], center[1], radius, steps));
  },
  measure({ coords, closed, step }) {
    check(isCoords(coords) && typeof closed === "boolean" && (step === undefined || (typeof step === "number" && step > 0)));
    input(coords);
    const measured = f64s(wasm.measure_path(closed ? 1 : 0));
    if (step === undefined) return { measured };
    input(closed && coords.byteLength > 16 ? closedRing(coords) : coords);
    return { measured, path: f64s(wasm.densify(step)) };
  },
};

// The ring with its first vertex repeated at the end.
function closedRing(coords) {
  const ring = new Float64Array(coords.byteLength / 8 + 2);
  ring.set(new Float64Array(coords));
  ring.copyWithin(ring.length - 2, 0, 2);
  return ring.buffer;
}

onmessage = async (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready && typeof msg.wasm === "string") {
    ready = WebAssembly.instantiateStreaming(fetch(msg.wasm), { Math }).then(({ instance }) => {
      wasm = instance.exports;
    });
  } else if (msg?.type === "call" && ready && Number.isInteger(msg.id) && Object.hasOwn(OPS, msg.op)) {
    try {
      await ready;
      const value = OPS[msg.op](msg);
      const buffers = value instanceof Float64Array ? [value.buffer] : Object.values(value).map((v) => v.buffer);
      postMessage({ type: "result", id: msg.id, value }, buffers);
    } catch (err) {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    }
  } else if (msg?.type === "call" && Number.isInteger(msg.id)) {
    postMessage({ type: "result", id: msg.id, error: "unknown call" });
  }
};
