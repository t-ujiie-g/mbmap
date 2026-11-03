// The showcase with the npm package's `Map` and the DOM.
import { Map } from "mbmap";
import { describe, RADIUS_METERS } from "../shared/analysis.js";
import { mountControls } from "../shared/controls.js";
import { mountPanel, panelControllers } from "../shared/panel.js";
import { pinDestinations, saveImage } from "../shared/overlay.js";
import { describeFeature, hoverPlaces } from "../shared/pick.js";
import { DESTINATIONS } from "../shared/places.js";
import { PLACES } from "../shared/places.js";
import { createStyle, modeCamera, withMarker } from "../shared/style.js";

let mode = "2d";
let places = PLACES;

const map = new Map({ container: "map", style: createStyle(mode), center: DESTINATIONS[0].center, zoom: 15, attributionControl: false });
map.on("move", showCamera);
map.on("moveend", update);
map.once("load").then(() => {
  window.__loaded = performance.now();
  update();
});
window.__map = map;
// The topmost feature under a click, from the workers that hold the geometry.
map.on("click", (e) => map.queryRenderedFeatures(e.point).then(showPicked));
hoverPlaces(map);
pinDestinations(map, document.body);
mountControls(map, document.body);
const panel = panelControllers(map, () => mode, () => places);
map.once("load").then(() => mountPanel(panel));

function showPicked(features) {
  const rows = describeFeature(features) ?? [["—", "何もありません"]];
  document.getElementById("picked").replaceChildren(...rows.flatMap(([k, v]) => [Object.assign(document.createElement("dt"), { textContent: k }), Object.assign(document.createElement("dd"), { textContent: v })]));
  window.__picked = rows;
}

// The style changes in place: tiles of what stays alike are kept.
function setMode(next) {
  if (next === mode) return;
  mode = next;
  map.setStyle(createStyle(mode, panel.hidden(), places, panel.basemaps.state.active ?? "map"));
  map.easeTo({ ...modeCamera(mode), duration: 1000 });
  showButtons();
}

function addMarker() {
  places = withMarker(places, map.getCenter(), `印 ${places.features.length - PLACES.features.length + 1}`);
  map.getSource("places").setData(places);
}

function showButtons() {
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
document.getElementById("marker").addEventListener("click", addMarker);
document.getElementById("save").addEventListener("click", () => saveImage(map));
showButtons();
showCamera();
