// An image, a video (red for a second, then blue) and a canvas source side by side, for the pack
// test's media check (bench/npm/checks/media.mjs).
import { Map } from "mbmap";

const box = (west, east) => [[west, 10], [east, 10], [east, -10], [west, -10]];
const paint = document.getElementById("paint").getContext("2d");
paint.fillStyle = "#ff0000";
paint.fillRect(0, 0, 16, 16);

const map = new Map({
  container: "map",
  center: [0, 0],
  zoom: 2,
  style: {
    version: 8,
    sources: {
      picture: { type: "image", url: "../../../../examples/shared/station-sketch.png", coordinates: box(-30, -10) },
      clip: { type: "video", urls: ["./clip.webm"], coordinates: box(-9, 9) },
      paint: { type: "canvas", canvas: "paint", coordinates: box(10, 30) },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#ffffff" } },
      { id: "picture", type: "raster", source: "picture" },
      { id: "clip", type: "raster", source: "clip" },
      { id: "paint", type: "raster", source: "paint" },
    ],
  },
});
map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  window.__loaded = performance.now();
});
window.__map = map;
window.__paint = paint;
