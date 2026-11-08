// A synthetic I3S 3DObject layer near Tokyo Station (./set, written by bench/i3s/synthetic.mjs) streamed by
// mbmap/3d's I3S layer, for the pack test's i3s check (bench/npm/checks/i3s.mjs).
import { Map } from "mbmap";
import { i3sLayer } from "mbmap/3d";

const map = new Map({
  container: "map",
  center: [139.7671, 35.6812],
  zoom: 17,
  pitch: 50,
  bearing: -20,
  attributionControl: false,
  style: { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#ffffff" } }] },
});
const layer = i3sLayer({ id: "buildings", url: new URL("./set/layers/0/layer.json", location.href).href });
map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  map.addLayer(layer);
  window.__loaded = performance.now();
});
window.__map = map;
window.__layer = layer;
// Resolves once nothing is asked for or loading and the nodes drawn stay the same for a few frames.
window.__settled = () => new Promise((done) => {
  let last = "";
  let same = 0;
  const check = () => {
    const now = window.__layer.selected.map((t) => t.path).sort().join();
    const busy = !window.__layer.idle || window.__layer.selected.length === 0;
    same = now === last && !busy && !map.isMoving() ? same + 1 : 0;
    last = now;
    if (same > 10) done();
    else {
      map.triggerRepaint();
      requestAnimationFrame(check);
    }
  };
  requestAnimationFrame(check);
});
