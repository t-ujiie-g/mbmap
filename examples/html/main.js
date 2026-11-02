// The showcase with the npm package's `Map` and the DOM.
import { Map } from "mbmap";
import { describe, RADIUS_METERS } from "../shared/analysis.js";
import { DESTINATIONS } from "../shared/places.js";
import { createStyle, modeCamera } from "../shared/style.js";

let mode = "2d";
let map = null;

function start(camera) {
  map?.remove();
  map = new Map({ container: "map", style: createStyle(mode), ...camera });
  map.on("move", showCamera);
  map.on("moveend", update);
  map.once("load").then(() => {
    window.__loaded = performance.now();
    update();
  });
  window.__map = map;
  showCamera();
}

function setMode(next) {
  if (next === mode) return;
  mode = next;
  const c = map.getCenter();
  // The style changes, so the map starts again where it was (setStyle comes in Phase 12.2).
  start({ center: [c.lng, c.lat], zoom: map.getZoom(), bearing: map.getBearing(), pitch: map.getPitch() });
  map.once("load").then(() => map.easeTo({ ...modeCamera(mode), duration: 1000 }));
  showModes();
}

function showModes() {
  for (const b of document.querySelectorAll("#modes button")) b.setAttribute("aria-pressed", String(b.dataset.mode === mode));
}

const fixed = (v, n) => v.toFixed(n);
let plane = null;

function showCamera() {
  const c = map.getCenter();
  const rows = [
    ["経度", fixed(c.lng, 5)],
    ["緯度", fixed(c.lat, 5)],
    ["ズーム", fixed(map.getZoom(), 2)],
    ["方位", `${fixed(map.getBearing(), 1)}°`],
    ["傾き", `${fixed(map.getPitch(), 1)}°`],
  ];
  if (plane) rows.push([`平面直角 ${plane.zone}`, `X ${fixed(plane.y, 1)} m`], ["", `Y ${fixed(plane.x, 1)} m`]);
  const dl = document.getElementById("camera");
  dl.replaceChildren(...rows.flatMap(([k, v]) => [Object.assign(document.createElement("dt"), { textContent: k }), Object.assign(document.createElement("dd"), { textContent: v })]));
}

let pending = 0;
async function update() {
  const ticket = ++pending;
  const result = await describe(map.getCenter());
  if (ticket !== pending) return;
  plane = result.plane;
  showCamera();
  const ul = document.getElementById("near");
  ul.replaceChildren(...(result.near.length ? result.near : [`なし（半径 ${RADIUS_METERS / 1000} km）`]).map((n) => Object.assign(document.createElement("li"), { textContent: n })));
  window.__described = result;
}

document.getElementById("modes").addEventListener("click", (e) => {
  if (e.target instanceof HTMLButtonElement) setMode(e.target.dataset.mode);
});
document.getElementById("destinations").replaceChildren(
  ...DESTINATIONS.map((d) => {
    const b = document.createElement("button");
    b.textContent = d.name;
    b.addEventListener("click", () => map.flyTo({ center: d.center, zoom: d.zoom, ...modeCamera(mode) }));
    return b;
  }),
);
start({ center: DESTINATIONS[0].center, zoom: 15 });
showModes();
