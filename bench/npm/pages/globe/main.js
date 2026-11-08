// The world's standard map on a globe, for the pack test's globe check (bench/npm/checks/globe.mjs).
import { Map } from "mbmap";

const map = new Map({
  container: "map",
  center: [139.7, 35.7],
  zoom: 1,
  attributionControl: false,
  style: {
    version: 8,
    projection: { type: "globe" },
    sources: {
      world: { type: "raster", tiles: [`${location.origin}/bench/fixtures/gsi-std-world/{z}/{x}/{y}.png`], tileSize: 256, maxzoom: 3 },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#203040" } },
      { id: "world", type: "raster", source: "world" },
    ],
  },
});
window.__map = map;
// Resolves once the map has every tile and is not moving, two frames on.
window.__settled = () => new Promise((done) => {
  let frames = 0;
  const check = () => (map.loaded() && !map.isMoving() && ++frames > 2 ? done() : requestAnimationFrame(check));
  requestAnimationFrame(check);
});
map.once("load").then(() => {
  window.__loaded = performance.now();
});
