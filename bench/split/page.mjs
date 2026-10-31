// For each module: start a fresh module worker (timing its start), load the
// module there and, for analysis modules, run it once cold and then warm.
const modules = {
  worker: "/_build/wasm-gc/release/build/worker/worker.wasm",
  combined: "/_build/wasm-gc/release/build/bench/split/combined_entry/combined_entry.wasm",
  analysis: "/_build/wasm-gc/release/build/bench/split/analysis_entry/analysis_entry.wasm",
  empty: "/_build/wasm-gc/release/build/bench/split/empty_entry/empty_entry.wasm",
};
const POLYGONS = 10000;

async function once(url) {
  const t0 = performance.now();
  const w = new Worker("/bench/split/load-worker.mjs", { type: "module" });
  const reply = () => new Promise((resolve, reject) => {
    w.onmessage = (e) => resolve(e.data);
    w.onerror = (e) => reject(new Error(e.message));
  });
  await reply();
  const spawnMs = performance.now() - t0;
  w.postMessage({ url, polygons: POLYGONS });
  const r = await reply();
  w.terminate();
  if (r.error) throw new Error(`${url}: ${r.error}`);
  return { spawnMs, ...r };
}

const runs = Number(new URLSearchParams(location.search).get("runs") ?? 7);
const result = { params: { runs, polygons: POLYGONS, statistic: "median of runs" }, modules: {} };
try {
  const samples = Object.fromEntries(Object.keys(modules).map((k) => [k, []]));
  // Interleave modules so drift affects them alike.
  for (let i = 0; i < runs; i++) {
    for (const [name, url] of Object.entries(modules)) samples[name].push(await once(url));
  }
  const med = (xs) => xs.sort((a, b) => a - b)[xs.length >> 1];
  for (const [name, rs] of Object.entries(samples)) {
    result.modules[name] = Object.fromEntries(Object.keys(rs[0]).map((k) => [k, med(rs.map((r) => r[k]))]));
  }
} catch (err) {
  result.error = String(err?.stack ?? err);
}
window.__result = result;
