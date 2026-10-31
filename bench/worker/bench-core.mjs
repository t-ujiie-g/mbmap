// The wasm-gc build of the `worker` package processing every fixture with
// examples/basic/style.json, as tile workers do: "cold" is a fresh instance
// handling each tile once in order (what a page's first tiles see), "warm"
// the per-tile median after warm-up.
import { runRows } from "../lib/rows.mjs";

export async function loadWorker(fetchBytes) {
  const { instance } = await WebAssembly.instantiate(await fetchBytes("_build/wasm-gc/release/build/worker/worker.wasm"), {});
  const e = instance.exports;
  const put = (bytes) => {
    const addr = e.prepare_input(bytes.length);
    new Uint8Array(e.memory.buffer, addr, bytes.length).set(bytes);
  };
  put(await fetchBytes("examples/basic/style.json"));
  if (e.init_style() !== 0) throw new Error("style failed");
  return (buf) => {
    put(buf);
    return e.process_tile(0, 14);
  };
}

const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[s.length >> 1]; };

export async function runWorkerBench(fetchBytes, tiles) {
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
