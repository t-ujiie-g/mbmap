// Loads the MoonBit builds of bench/backend/entry.
// `fetchBytes(relPath)` and `importJs(relPath)` are supplied by the host;
// paths are relative to the repository root.

export const BUILD = {
  wasm: "_build/wasm/release/build/bench/backend/entry/entry.wasm",
  wasmOpt: "bench/dist/entry.wasm-opt.wasm",
  wasmgc: "_build/wasm-gc/release/build/bench/backend/entry/entry.wasm",
  wasmgcOpt: "bench/dist/entry.wasm-gc-opt.wasm",
  js: "_build/js/release/build/bench/backend/entry/entry.js",
};

export async function loadModules({ fetchBytes, importJs }) {
  const modules = {};
  const load = {};
  for (const key of ["wasm", "wasmOpt", "wasmgc", "wasmgcOpt"]) {
    const t0 = performance.now();
    try {
      const bytes = await fetchBytes(BUILD[key]);
      const { instance } = await WebAssembly.instantiate(bytes, {});
      modules[key] = instance.exports;
    } catch (err) {
      load[key] = { error: String(err) };
      continue;
    }
    load[key] = { fetchAndInstantiateMs: performance.now() - t0 };
  }
  const t0 = performance.now();
  modules.js = await importJs(BUILD.js);
  load.js = { importMs: performance.now() - t0 };
  return { modules, load };
}
