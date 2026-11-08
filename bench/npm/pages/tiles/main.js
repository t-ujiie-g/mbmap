// Blocks near Tokyo Station as 3D Tiles 1.0 b3dm (./set, written by bench/tiles/synthetic.mjs) streamed by
// mbmap/3d's tiles layer, for the pack test's tiles check (bench/npm/checks/tiles.mjs), which also
// streams PLATEAU's buildings (bench/fixtures/plateau-chiyoda, Draco-compressed b3dm).
import { Map } from "mbmap";
import { tilesLayer } from "mbmap/3d";

const map = new Map({
  container: "map",
  center: [139.7671, 35.6812],
  zoom: 16,
  pitch: 60,
  bearing: -20,
  attributionControl: false,
  style: { version: 8, sources: {}, layers: [{ id: "background", type: "background", paint: { "background-color": "#ffffff" } }] },
});
const layer = tilesLayer({ id: "blocks", url: new URL("./set/tileset.json", location.href).href });
map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  map.addLayer(layer);
  window.__loaded = performance.now();
});
window.__map = map;
window.__layer = layer;
window.__tilesLayer = tilesLayer;
// Resolves once nothing is asked for or loading and the tiles drawn stay the same for a few frames.
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
