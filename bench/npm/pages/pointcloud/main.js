// A LAS point cloud (./cloud.las, written by bench/las/synthetic.mjs in plane rectangular IX) drawn by
// mbmap/3d's point cloud layer, for the pack test's pointcloud check (bench/npm/checks/pointcloud.mjs).
import { Map } from "mbmap";
import { pointCloudLayer } from "mbmap/3d";

const map = new Map({
  container: "map",
  center: [139.7671, 35.6812],
  zoom: 17,
  pitch: 50,
  bearing: -20,
  attributionControl: false,
  style: { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#ffffff" } }] },
});
const layer = pointCloudLayer({ id: "cloud", url: new URL("./cloud.las", location.href).href, pointSize: 3 });
map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  map.addLayer(layer);
  window.__loaded = performance.now();
});
window.__map = map;
window.__layer = layer;
window.__pointCloudLayer = pointCloudLayer;
