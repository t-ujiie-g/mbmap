// The showcase with the npm package's `Map` and the DOM.
import { Map } from "mbmap";
import { mountApp } from "../shared/app.js";
import { DESTINATIONS } from "../shared/places.js";
import { mountShell } from "../shared/shell.js";
import { createStyle } from "../shared/style.js";

const { status } = mountShell("html");
const map = new Map({ container: "map", style: createStyle("2d"), center: DESTINATIONS[0].center, zoom: 15, attributionControl: false });
window.__map = map;
map.once("load").then(() => {
  window.__loaded = performance.now();
  const app = mountApp(map, status, (style) => map.setStyle(style));
  map.on("move", app.showCamera);
  map.on("moveend", app.update);
});
