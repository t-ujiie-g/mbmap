// A glTF box (quantized and meshopt-compressed, bench/model/pack-model.mjs) placed by mbmap/3d's model
// layer, for the pack test's model check (bench/npm/checks/model.mjs).
import { Map } from "mbmap";
import { modelLayer } from "mbmap/3d";

const map = new Map({
  container: "map",
  center: [139.7671, 35.6812],
  zoom: 17,
  attributionControl: false,
  style: {
    version: 8,
    sources: {
      block: { type: "geojson", data: { type: "Polygon", coordinates: [[[139.7674, 35.6806], [139.7678, 35.6806], [139.7678, 35.6809], [139.7674, 35.6809], [139.7674, 35.6806]]] } },
      low: { type: "geojson", data: { type: "Polygon", coordinates: [[[139.7676, 35.68046], [139.768, 35.68046], [139.768, 35.6806], [139.7676, 35.6806], [139.7676, 35.68046]]] } },
      tall: { type: "geojson", data: { type: "Polygon", coordinates: [[[139.70, 35.70], [139.72, 35.70], [139.72, 35.71], [139.70, 35.71], [139.70, 35.70]]] } },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#ffffff" } },
      { id: "block", type: "fill-extrusion", source: "block", paint: { "fill-extrusion-color": "#2080c0", "fill-extrusion-height": 20 } },
      { id: "low", type: "fill-extrusion", source: "low", paint: { "fill-extrusion-color": "#2080c0", "fill-extrusion-height": 5 } },
      { id: "tall", type: "fill-extrusion", source: "tall", paint: { "fill-extrusion-color": "#2080c0", "fill-extrusion-height": 500 } },
    ],
  },
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
