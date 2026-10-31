// The npm package as an app uses it: `import { Map } from "mbmap"`, with the
// style given by URL. Tiles are the z14 bench fixtures around Tokyo Station.
import { Map } from "mbmap";

const map = new Map({
  container: "map",
  style: "/examples/basic/style.json",
  center: [139.7671, 35.6812],
  zoom: 14.5,
});
map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  window.__loaded = performance.now();
});
window.__map = map;
