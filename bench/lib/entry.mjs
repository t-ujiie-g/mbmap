// Loads the js and wasm-gc builds of bench/entry (the MoonBit export surface
// shared by the mvt and tess benches).
import { hostNumber } from "../../wasmio/js/host.mjs";

export const ENTRY_JS = "_build/js/release/build/bench/entry/entry.js";
export const ENTRY_WASM_GC = "_build/wasm-gc/release/build/bench/entry/entry.wasm";

const WASM_PAGE = 65536;

// `copyIn` places a tile in linear memory from the second page on and returns
// its address, for the *_mem exports.
export async function loadWasmGc(fetchBytes) {
  // The GeoJSON tiler and proj compute with the host's Math, and the reader parses long numbers
  // with its Number() (bench/entry/host_math.mbt).
  let e = null;
  const host = { number: hostNumber(() => e.memory) };
  const { instance } = await WebAssembly.instantiate(await fetchBytes(ENTRY_WASM_GC), { Math, host });
  e = instance.exports;
  const base = WASM_PAGE;
  return {
    exports: e,
    copyIn(buf) {
      const need = base + buf.length - e.memory.buffer.byteLength;
      if (need > 0) e.grow_memory(Math.ceil(need / WASM_PAGE));
      new Uint8Array(e.memory.buffer, base, buf.length).set(buf);
      return base;
    },
  };
}

// `importJs(relPath)` is `import()` of a repo-relative path for the host.
export async function loadEntry(fetchBytes, importJs) {
  return { mbtJs: await importJs(ENTRY_JS), gc: await loadWasmGc(fetchBytes) };
}

export const workerImportJs = (rel) => import(`/${rel}`);
