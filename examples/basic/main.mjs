// Basic example: serve the repository root (node bench/lib/serve.mjs via the
// example runner, or any static server) and open /examples/basic/.
import * as mbmap from "/_build/js/release/build/bundle/main/main.js";

const style = await (await fetch("./style.json")).text();
const map = mbmap.create_map(
  document.getElementById("map"),
  style,
  139.7671, 35.6812, 14.5,
  "/worker/js/worker.mjs",
  "/_build/wasm-gc/release/build/worker/worker.wasm",
  0, // tile workers: 0 = half the hardware threads, at most 4
);
window.__map = map;
window.__mbmap = mbmap;
mbmap.map_on_idle(map, () => { window.__idle = performance.now(); });
