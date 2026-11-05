// The showcase with <mb-map>: attributes and properties in, CustomEvents out.
import "mbmap/element";
import { mountApp } from "../shared/app.js";
import { mountShell } from "../shared/shell.js";
import { createStyle } from "../shared/style.js";

const { status } = mountShell("element");
const el = document.querySelector("mb-map");
el.addEventListener("mb-load", () => {
  window.__loaded = performance.now();
  window.__map = el.map;
  // A new style object goes to the map's setStyle: tiles of what stays alike are kept.
  const app = mountApp(el.map, status, (style) => (el.mapStyle = style));
  el.addEventListener("mb-move", app.showCamera);
  el.addEventListener("mb-moveend", app.update);
});
el.mapStyle = createStyle("2d");
