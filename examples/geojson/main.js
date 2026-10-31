// GeoJSON sources from the style: one by URL (places.geojson), one inline.
// mbmap loads its GeoJSON module and worker only because the style has them.
import { Map } from "mbmap";

const params = new URLSearchParams(location.search);
const map = new Map({
  container: "map",
  style: "./style.json",
  center: [139.7630, 35.6810],
  zoom: Number(params.get("zoom") ?? 15),
  pitch: Number(params.get("pitch") ?? 0),
  bearing: Number(params.get("bearing") ?? 0),
});
map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  window.__loaded = performance.now();
});
window.__map = map;
