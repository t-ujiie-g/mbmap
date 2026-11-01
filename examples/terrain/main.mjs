// `npm --prefix bench run example`, then /examples/terrain/: Mt Fuji in 3D
// with its hillshade, from the z12 DEM fixtures or GSI's live DEM tiles
// (z1-14) with `?remote=1`. `?zoom=`, `?bearing=` and `?pitch=` set the camera.
import * as mbmap from "/_build/js/release/build/bundle/main/main.js";

const GSI_DEM = "https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png";

const params = new URLSearchParams(location.search);
const style = await (await fetch("./style.json")).json();
if (params.get("remote") === "1") Object.assign(style.sources.dem, { tiles: [GSI_DEM], minzoom: 1, maxzoom: 14 });

const map = mbmap.create_map(
  document.getElementById("map"),
  JSON.stringify(style),
  138.7274, 35.3606, Number(params.get("zoom") ?? 11.3),
  Number(params.get("bearing") ?? -20), Number(params.get("pitch") ?? 60),
  "/worker/js/worker.mjs",
  "/_build/wasm-gc/release/build/worker/worker.wasm",
  0,
  null,
  "sans-serif",
);
window.__map = map;
mbmap.map_on_idle(map, () => { window.__idle = performance.now(); });
