// The wasm-gc worker processing every fixture with bench/maplibre/style.json:
// "cold" is a fresh instance taking each tile once, "warm" the median after warm-up.
import { hostText } from "../../wasmio/js/host.mjs";
import { median, runRows } from "../lib/rows.mjs";

const put = (e, bytes) => {
  const addr = e.prepare_input(bytes.length);
  new Uint8Array(e.memory.buffer, addr, bytes.length).set(bytes);
};

// The style as the main thread hands it to display workers (docs/FORMATS.md "Compiled style").
async function compiledStyle(fetchBytes) {
  const { instance } = await WebAssembly.instantiate(await fetchBytes("_build/wasm-gc/release/build/bench/worker/compile_entry/compile_entry.wasm"), {});
  const c = instance.exports;
  put(c, await fetchBytes("bench/maplibre/style.json"));
  const n = c.compile_style();
  if (n < 0) throw new Error("style failed to compile");
  return new Uint8Array(c.memory.buffer, c.output_addr(), n).slice();
}

export async function loadWorker(fetchBytes) {
  const { instance } = await WebAssembly.instantiate(await fetchBytes("_build/wasm-gc/release/build/worker/worker.wasm"), { host: hostText(), Math });
  const e = instance.exports;
  put(e, await compiledStyle(fetchBytes));
  if (e.init_style() !== 0) throw new Error("style failed");
  return (buf) => {
    put(e, buf);
    return e.process_tile(0, 14);
  };
}


export async function runTileBench(fetchBytes, tiles) {
  const cold = await loadWorker(fetchBytes);
  const coldMs = [];
  let outputBytes = 0;
  for (const t of tiles) {
    const t0 = performance.now();
    const n = cold(t.buf);
    coldMs.push(performance.now() - t0);
    if (n < 0) throw new Error(`process failed for ${t.key}`);
    outputBytes += n;
  }
  const warm = await loadWorker(fetchBytes);
  const result = await runRows(tiles, [{ name: "worker process_tile (warm)", run: (t) => warm(t.buf) }]);
  return {
    ...result,
    cold: { firstTileMs: coldMs[0], medianTileMs: median(coldMs), totalMs: coldMs.reduce((a, b) => a + b, 0) },
    outputBytes,
  };
}
