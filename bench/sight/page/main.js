// The boxes of ./boxes.mjs for bench/sight/golden.mjs: extrusions and mbmap/3d's model layer.
import { Map } from "mbmap";
import { modelLayer } from "mbmap/3d";
import { BOXES, CENTER, MODEL } from "./boxes.mjs";

const polygon = ([w, s, e, n, height]) => ({ type: "Feature", properties: { height }, geometry: { type: "Polygon", coordinates: [[[w, s], [e, s], [e, n], [w, n], [w, s]]] } });
const map = new Map({
  container: "map",
  center: CENTER,
  zoom: 16.5,
  pitch: 55,
  bearing: 20,
  attributionControl: false,
  style: {
    version: 8,
    sources: { boxes: { type: "geojson", data: { type: "FeatureCollection", features: BOXES.map(polygon) } } },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#ffffff" } },
      { id: "boxes", type: "fill-extrusion", source: "boxes", paint: { "fill-extrusion-color": "#808080", "fill-extrusion-height": ["get", "height"] } },
    ],
  },
});
const layer = modelLayer({ id: "box", model: new URL("./box.glb", location.href).href, data: { type: "Point", coordinates: MODEL } });
map.once("load").then(async () => {
  map.addLayer(layer);
  await layer.ready;
  window.__loaded = true;
});
window.__map = map;
window.__layer = layer;
window.__settled = () => new Promise((done) => {
  let frames = 0;
  const check = () => (map.loaded() && !map.isMoving() && ++frames > 2 ? done() : requestAnimationFrame(check));
  requestAnimationFrame(check);
});
