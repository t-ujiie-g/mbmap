// Basic example: `npm --prefix bench run example`, then open /examples/basic/.
// By default the style reads the z14 bench fixtures around Tokyo Station;
// `?remote=1` reads GSI's live tiles (z4-16) instead, so the map works at
// every zoom and everywhere in Japan.
import * as mbmap from "/_build/js/release/build/bundle/main/main.js";

const GSI_TILES = "https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/{z}/{x}/{y}.pbf";

const params = new URLSearchParams(location.search);
let style = await (await fetch("./style.json")).text();
if (params.get("remote") === "1") {
  const json = JSON.parse(style);
  Object.assign(json.sources.gsi, { tiles: [GSI_TILES], minzoom: 4, maxzoom: 16 });
  style = JSON.stringify(json);
}

const map = mbmap.create_map(
  document.getElementById("map"),
  style,
  139.7671, 35.6812, Number(params.get("zoom") ?? 14.5),
  "/worker/js/worker.mjs",
  "/_build/wasm-gc/release/build/worker/worker.wasm",
  0, // tile workers: 0 = half the hardware threads, at most 4
);
window.__map = map;
window.__mbmap = mbmap;
mbmap.map_on_idle(map, () => { window.__idle = performance.now(); });
