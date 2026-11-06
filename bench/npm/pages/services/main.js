// A map of GSI's standard tiles for the pack test's services check (bench/npm/checks/services.mjs),
// which adds sources made by mbmap/services from the capabilities documents next to this page.
import { Map } from "mbmap";

const map = new Map({
  container: "map",
  center: [139.7671, 35.6812],
  zoom: 14,
  style: {
    version: 8,
    sources: { gsi: { type: "raster", tiles: ["../../../fixtures/gsi-std/{z}/{x}/{y}.png"], tileSize: 256, minzoom: 14, maxzoom: 14 } },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#ffffff" } },
      { id: "gsi", type: "raster", source: "gsi" },
    ],
  },
});
map.on("error", (e) => console.error(e.error));
window.__map = map;
map.once("idle").then(() => {
  window.__loaded = true;
});
