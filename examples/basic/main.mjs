// `npm --prefix bench run example`, then /examples/basic/: the z14 fixtures, or
// GSI's live tiles with `?remote=1`. `?zoom=`, `?bearing=`, `?pitch=` set the
// camera; `?terrain=1` raises it on GSI's DEM (`&exaggeration=`); right-drag
// (or Ctrl+drag) rotates and tilts.
import * as mbmap from "/_build/js/release/build/bundle/main/main.js";

const GSI_TILES = "https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/{z}/{x}/{y}.pbf";

const params = new URLSearchParams(location.search);
let style = await (await fetch("./style.json")).text();
if (params.get("terrain") === "1") {
  // GSI's DEM under the map: the z14 fixtures, or live tiles with ?remote=1.
  const json = JSON.parse(style);
  json.sources.dem = { type: "raster-dem", tiles: ["/bench/fixtures/gsi-dem/{z}/{x}/{y}.png"], tileSize: 256, minzoom: 14, maxzoom: 14, encoding: "gsi" };
  json.terrain = { source: "dem", exaggeration: Number(params.get("exaggeration") ?? 3) };
  json.sky = { "sky-color": "#88C6FC", "horizon-color": "#ffffff", "fog-color": "#ffffff" };
  style = JSON.stringify(json);
}
if (params.get("remote") === "1") {
  const json = JSON.parse(style);
  Object.assign(json.sources.gsi, { tiles: [GSI_TILES], minzoom: 4, maxzoom: 16 });
  if (json.sources.dem) Object.assign(json.sources.dem, { tiles: ["https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png"], minzoom: 1, maxzoom: 14 });
  style = JSON.stringify(json);
}

const map = mbmap.create_map(
  document.getElementById("map"),
  style,
  139.7671, 35.6812, Number(params.get("zoom") ?? 14.5),
  Number(params.get("bearing") ?? 0), Number(params.get("pitch") ?? 0),
  "/worker/js/worker.mjs",
  "/_build/wasm-gc/release/build/worker/worker.wasm",
  0, // tile workers: 0 = half the hardware threads, at most 4
  null, // no GeoJSON sources
  "sans-serif", // labels' font family
);
window.__map = map;
window.__mbmap = mbmap;
mbmap.map_on_idle(map, () => { window.__idle = performance.now(); });
