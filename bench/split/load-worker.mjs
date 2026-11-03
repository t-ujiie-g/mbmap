// Module worker for bench/split: on {url, polygons}, loads one wasm-gc module
// and, if it exports `analyze`, runs it on synthetic columnar polygons.
// Replies with timings in ms.
function polygons(count) {
  // Deterministic squares with 4-40 points around Japan, no holes.
  let seed = 1;
  const rand = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
  const rings = [], ends = [], coords = [];
  for (let p = 0; p < count; p++) {
    const n = 4 + Math.floor(rand() * 37);
    const cx = 130 + rand() * 15, cy = 30 + rand() * 15, r = 0.001 + rand() * 0.01;
    for (let i = 0; i < n; i++) {
      const a = (i / n) * 2 * Math.PI;
      coords.push(cx + r * Math.cos(a), cy + r * Math.sin(a));
    }
    rings.push(coords.length / 2);
    ends.push(rings.length);
  }
  const bytes = new Uint8Array((rings.length + ends.length) * 4 + coords.length * 8);
  const view = new DataView(bytes.buffer);
  let o = 0;
  for (const v of [...rings, ...ends]) { view.setInt32(o, v, true); o += 4; }
  for (const v of coords) { view.setFloat64(o, v, true); o += 8; }
  return { bytes, rings: rings.length, polys: ends.length, points: coords.length / 2 };
}

onmessage = (e) => measure(e.data).catch((err) => postMessage({ error: String(err?.stack ?? err) }));

async function measure({ url, polygons: count }) {
  const t0 = performance.now();
  // The display worker parses long JSON numbers with the host's Number() (unused here).
  const { instance } = await WebAssembly.instantiateStreaming(fetch(url), { host: { number: () => NaN, text_char() {}, text_number: () => NaN, number_text: () => 0, text_code: () => 0 }, Math });
  const loadMs = performance.now() - t0;
  const e = instance.exports;
  if (!e.analyze) return postMessage({ loadMs });
  const input = polygons(count);
  const run = () => {
    // The linked-in variant names the analysis input separately.
    const addr = (e.prepare_analysis_input ?? e.prepare_input)(input.bytes.length);
    new Uint8Array(e.memory.buffer, addr, input.bytes.length).set(input.bytes);
    const t = performance.now();
    const n = e.analyze(input.rings, input.polys, input.points);
    if (n < 0) throw new Error("analyze failed");
    return performance.now() - t;
  };
  const firstMs = run();
  const warm = Array.from({ length: 9 }, run).sort((a, b) => a - b);
  postMessage({ loadMs, firstMs, warmMs: warm[4] });
}
postMessage({ ready: true });
