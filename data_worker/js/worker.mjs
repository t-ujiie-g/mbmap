// Glue around the wasm-gc build of `data_worker`; messages are in
// docs/FORMATS.md ("Data worker messages").

import { hostNumber, MAX_INPUT_BYTES } from "../../wasmio/js/host.mjs";
import { fetchInit, readCapped } from "../../worker/js/body.mjs";

const decoder = new TextDecoder();
const encoder = new TextEncoder();
let wasm = null;
let ready = null;

function check(ok) {
  if (!ok) throw new Error("invalid arguments");
}

function input(parts) {
  const len = parts.reduce((s, b) => s + b.length, 0);
  const addr = wasm.prepare_input(len);
  if (addr < 0) throw new Error(`input too large (${len} bytes)`);
  let at = addr;
  for (const b of parts) {
    new Uint8Array(wasm.memory.buffer, at, b.length).set(b);
    at += b.length;
  }
}

// The table bytes a reader wrote, or the error it reported.
function table(n) {
  const at = wasm.output_addr();
  if (n === -2) throw new Error("out of memory");
  if (n < 0) throw new Error(decoder.decode(new Uint8Array(wasm.memory.buffer, at, -n)));
  return wasm.memory.buffer.slice(at, at + n);
}

// The data of a `read` call: fetched (http(s) only, no credentials unless `init`
// asks for them), a Blob's bytes, or bytes given; at most MAX_INPUT_BYTES.
async function bytesOf({ url, init, blob, bytes }) {
  if (bytes instanceof ArrayBuffer) {
    check(bytes.byteLength <= MAX_INPUT_BYTES);
    return new Uint8Array(bytes);
  }
  if (blob instanceof Blob) {
    if (blob.size > MAX_INPUT_BYTES) throw new Error(`data larger than ${MAX_INPUT_BYTES} bytes`);
    return new Uint8Array(await blob.arrayBuffer());
  }
  check(typeof url === "string" && /^https?:/i.test(url));
  const res = await fetch(url, fetchInit(init));
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return readCapped(res, MAX_INPUT_BYTES);
}

const isName = (n) => n === undefined || (typeof n === "string" && n.length > 0 && !n.includes("\0"));

async function read(msg) {
  const { format, options = {} } = msg;
  check(["csv", "wkt", "wkb"].includes(format) && options && typeof options === "object");
  const data = await bytesOf(msg);
  if (format === "wkt") {
    input([data]);
    return table(wasm.read_wkt());
  }
  if (format === "wkb") {
    input([data]);
    return table(wasm.read_wkb());
  }
  const { delimiter = -1, header = true, dynamicTyping = true, latitude, longitude, geometry } = options;
  check(Number.isInteger(delimiter) && typeof header === "boolean" && typeof dynamicTyping === "boolean");
  check([latitude, longitude, geometry].every(isName));
  const names = encoder.encode(`${latitude ?? ""}\0${longitude ?? ""}\0${geometry ?? ""}\0`);
  input([names, data]);
  return table(wasm.read_csv(names.length, delimiter, header ? 1 : 0, dynamicTyping ? 1 : 0));
}

const OPS = { read };

onmessage = async (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready && typeof msg.wasm === "string") {
    const host = { number: hostNumber(() => wasm.memory) };
    ready = WebAssembly.instantiateStreaming(fetch(msg.wasm), { host }).then(({ instance }) => {
      wasm = instance.exports;
    });
  } else if (msg?.type === "call" && ready && Number.isInteger(msg.id) && Object.hasOwn(OPS, msg.op)) {
    try {
      await ready;
      const value = await OPS[msg.op](msg);
      postMessage({ type: "result", id: msg.id, value }, [value]);
    } catch (err) {
      postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
    }
  }
};
