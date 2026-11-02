// The showcase with <mb-map>: attributes and properties in, CustomEvents out.
import "mbmap/element";
import { describe, RADIUS_METERS } from "../shared/analysis.js";
import { describeFeature } from "../shared/pick.js";
import { DESTINATIONS } from "../shared/places.js";
import { PLACES } from "../shared/places.js";
import { LAYER_GROUPS, createStyle, modeCamera, withMarker } from "../shared/style.js";

const el = document.querySelector("mb-map");
let mode = "2d";
const hidden = new Set();
let places = PLACES;

// A new style object goes to the map's setStyle: tiles of what stays alike are kept.
function setMode(next) {
  if (next === mode) return;
  mode = next;
  el.mapStyle = createStyle(mode, hidden, places);
  el.map?.easeTo({ ...modeCamera(mode), duration: 1000 });
  showButtons();
}

function toggle(group) {
  if (hidden.has(group.name)) hidden.delete(group.name);
  else hidden.add(group.name);
  const visibility = hidden.has(group.name) ? "none" : "visible";
  for (const id of group.ids) if (el.map?.getLayer(id)) el.map.setLayoutProperty(id, "visibility", visibility);
  showButtons();
}

function addMarker() {
  places = withMarker(places, el.center, `印 ${places.features.length - PLACES.features.length + 1}`);
  el.map?.getSource("places").setData(places);
}

function showButtons() {
  for (const b of document.querySelectorAll("#modes button")) b.setAttribute("aria-pressed", String(b.dataset.mode === mode));
  for (const b of document.querySelectorAll("#layers button")) b.setAttribute("aria-pressed", String(!hidden.has(b.textContent)));
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
  // The topmost feature under a click, from the workers that hold the geometry.
  map.on("click", (e) => map.queryRenderedFeatures(e.point).then(showPicked));
  map.on("mouseenter", "places", () => (map.getCanvas().style.cursor = "pointer"));
  map.on("mouseleave", "places", () => (map.getCanvas().style.cursor = ""));
  update();
});

function showPicked(features) {
  const rows = describeFeature(features) ?? [["—", "何もありません"]];
  document.getElementById("picked").replaceChildren(...rows.flatMap(([k, v]) => [Object.assign(document.createElement("dt"), { textContent: k }), Object.assign(document.createElement("dd"), { textContent: v })]));
  window.__picked = rows;
}
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
document.getElementById("layers").replaceChildren(
  ...LAYER_GROUPS.map((g) => {
    const b = document.createElement("button");
    b.textContent = g.name;
    b.addEventListener("click", () => toggle(g));
    return b;
  }),
);
document.getElementById("marker").addEventListener("click", addMarker);
el.mapStyle = createStyle(mode);
showButtons();
showCamera();
