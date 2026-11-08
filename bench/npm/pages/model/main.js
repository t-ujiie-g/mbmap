// A glTF box (quantized and meshopt-compressed, bench/model/pack-model.mjs) placed by mbmap/3d's model
// layer, for the pack test's model check (bench/npm/checks/model.mjs).
import { Map } from "mbmap";
import { modelLayer } from "mbmap/3d";

const map = new Map({
  container: "map",
  center: [139.7671, 35.6812],
  zoom: 17,
  attributionControl: false,
  style: { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#ffffff" } }] },
});
const layer = modelLayer({
  id: "boxes",
  model: new URL("./box.glb", location.href).href,
  data: {
    type: "FeatureCollection",
    features: [
      { type: "Feature", properties: { turn: 0, size: [1, 1, 1] }, geometry: { type: "Point", coordinates: [139.7671, 35.6812] } },
      { type: "Feature", properties: { turn: 45, size: [1, 1, 1] }, geometry: { type: "Point", coordinates: [139.7681, 35.6812] } },
    ],
  },
  rotation: [0, 0, ["get", "turn"]],
  scale: ["get", "size"],
});
map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  map.addLayer(layer);
  window.__loaded = performance.now();
});
window.__map = map;
window.__layer = layer;
// Resolves once the map has every tile and is not moving, two frames on.
window.__settled = () => new Promise((done) => {
  let frames = 0;
  const check = () => (map.loaded() && !map.isMoving() && ++frames > 2 ? done() : requestAnimationFrame(check));
  requestAnimationFrame(check);
});
