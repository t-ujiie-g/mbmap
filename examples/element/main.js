// The showcase with <mb-map>: attributes and properties in, CustomEvents out.
import "mbmap/element";
import { describe, RADIUS_METERS } from "../shared/analysis.js";
import { mountControls } from "../shared/controls.js";
import { mountPanel, panelControllers } from "../shared/panel.js";
import { pinDestinations, saveImage } from "../shared/overlay.js";
import { mountCoordinates } from "../shared/coordinates.js";
import { hoverPlaces, mountIdentify } from "../shared/pick.js";
import { DESTINATIONS } from "../shared/places.js";
import { PLACES } from "../shared/places.js";
import { createStyle, modeCamera, withMarker } from "../shared/style.js";

const el = document.querySelector("mb-map");
let mode = "2d";
let panel = null;
let places = PLACES;

// A new style object goes to the map's setStyle: tiles of what stays alike are kept.
function setMode(next) {
  if (next === mode) return;
  mode = next;
  el.mapStyle = createStyle(mode, panel?.hidden(), places, panel?.basemaps.state.active ?? "map");
  el.map?.easeTo({ ...modeCamera(mode), duration: 1000 });
  showButtons();
}

function addMarker() {
  places = withMarker(places, el.center, `印 ${places.features.length - PLACES.features.length + 1}`);
  el.map?.getSource("places").setData(places);
}

function showButtons() {
  for (const b of document.querySelectorAll("#modes button")) b.setAttribute("aria-pressed", String(b.dataset.mode === mode));
}

const fixed = (v, n) => v.toFixed(n);
let plane = null;

function showCamera() {
  const c = el.center;
  const rows = [
    ["経度", fixed(c.lng, 5)],
    ["緯度", fixed(c.lat, 5)],
    ["ズーム", fixed(el.zoom, 2)],
    ["方位", `${fixed(el.bearing, 1)}°`],
    ["傾き", `${fixed(el.pitch, 1)}°`],
  ];
  if (plane) rows.push([`平面直角 ${plane.zone}`, `X ${fixed(plane.y, 1)} m`], ["", `Y ${fixed(plane.x, 1)} m`]);
  document.getElementById("camera").replaceChildren(...rows.flatMap(([k, v]) => [Object.assign(document.createElement("dt"), { textContent: k }), Object.assign(document.createElement("dd"), { textContent: v })]));
}

let pending = 0;
async function update() {
  const ticket = ++pending;
  const result = await describe(el.center);
  if (ticket !== pending) return;
  plane = result.plane;
  showCamera();
  document.getElementById("near").replaceChildren(...(result.near.length ? result.near : [`なし（半径 ${RADIUS_METERS / 1000} km）`]).map((n) => Object.assign(document.createElement("li"), { textContent: n })));
  window.__described = result;
}

el.addEventListener("mb-move", showCamera);
el.addEventListener("mb-moveend", update);
el.addEventListener("mb-load", () => {
  window.__loaded = performance.now();
  window.__map = el.map;
  const map = el.map;
  // The features under a click, from the workers that hold the geometry.
  mountIdentify(map);
  mountCoordinates(map, document.body);
  hoverPlaces(map);
  pinDestinations(map, document.body);
  mountControls(map, document.body);
  panel = panelControllers(map, () => mode, () => places);
  mountPanel(panel);
  update();
});

document.getElementById("modes").addEventListener("click", (e) => {
  if (e.target instanceof HTMLButtonElement) setMode(e.target.dataset.mode);
});
document.getElementById("destinations").replaceChildren(
  ...DESTINATIONS.map((d) => {
    const b = document.createElement("button");
    b.textContent = d.name;
    b.addEventListener("click", () => el.map?.flyTo({ center: d.center, zoom: d.zoom, ...modeCamera(mode) }));
    return b;
  }),
);
document.getElementById("marker").addEventListener("click", addMarker);
document.getElementById("save").addEventListener("click", () => el.map && saveImage(el.map));
el.mapStyle = createStyle(mode);
showButtons();
showCamera();
